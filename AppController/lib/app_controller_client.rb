#!/usr/bin/ruby -w
# Programmer: Chris Bunch


require 'openssl'
require 'soap/rpc/driver'
require 'timeout'


require 'custom_exceptions'
require 'helperfunctions'


IP_REGEX = /\d+\.\d+\.\d+\.\d+/


FQDN_REGEX = /[\w\d\.\-]+/


IP_OR_FQDN = /#{IP_REGEX}|#{FQDN_REGEX}/


# Sometimes SOAP calls take a long time if large amounts of data are being
# sent over the network: for this first version we don't want these calls to
# endlessly timeout and retry, so as a hack, just don't let them timeout.
# The next version should replace this and properly timeout and not use
# long calls unless necessary.
NO_TIMEOUT = 100000


RETRY_ON_FAIL = true


ABORT_ON_FAIL = false


# A client that uses SOAP messages to communicate with the underlying cloud
# platform (here, AppScale). This client is similar to that used in the AppScale
# Tools, but with non-Neptune SOAP calls removed.
class AppControllerClient


  # The SOAP client that we use to communicate with the AppController.
  attr_accessor :conn
      

  # The IP address of the AppController that we will be connecting to.
  attr_accessor :ip
            

  # The secret string that is used to authenticate this client with
  # AppControllers. It is initially generated by appscale-run-instances and can
  # be found on the machine that ran that tool, or on any AppScale machine.
  attr_accessor :secret


  # A constructor that requires both the IP address of the machine to communicate
  # with as well as the secret (string) needed to perform communication.
  # AppControllers will reject SOAP calls if this secret (basically a password)
  # is not present - it can be found in the user's .appscale directory, and a
  # helper method is usually present to fetch this for us.
  def initialize(ip, secret)
    @ip = ip
    @secret = secret
    
    @conn = SOAP::RPC::Driver.new("https://#{@ip}:17443")
    @conn.add_method("set_parameters", "djinn_locations", "database_credentials", "app_names", "secret")
    @conn.add_method("set_apps", "app_names", "secret")
    @conn.add_method("set_apps_to_restart", "apps_to_restart", "secret")
    @conn.add_method("status", "secret")
    @conn.add_method("get_stats", "secret")
    @conn.add_method("update", "app_names", "secret")
    @conn.add_method("stop_app", "app_name", "secret")    
    @conn.add_method("get_all_public_ips", "secret")
    @conn.add_method("is_done_loading", "secret")
    @conn.add_method("is_done_initializing", "secret")
    @conn.add_method("add_role", "new_role", "secret")
    @conn.add_method("remove_role", "old_role", "secret")
    @conn.add_method("get_queues_in_use", "secret")
    @conn.add_method("add_appserver_to_haproxy", "app_id", "ip", "port",
      "secret")
    @conn.add_method("remove_appserver_from_haproxy", "app_id", "ip", "port",
      "secret")
    @conn.add_method("add_appserver_process", "app_id", "secret")
    @conn.add_method("remove_appserver_process", "app_id", "port", "secret")
  end
  

  # A helper method that makes SOAP calls for us. This method is mainly here to
  # reduce code duplication: all SOAP calls expect a certain timeout and can
  # tolerate certain exceptions, so we consolidate this code into this method.
  # Here, the caller specifies the timeout for the SOAP call (or NO_TIMEOUT
  # if an infinite timeout is required) as well as whether the call should
  # be retried in the face of exceptions. Exceptions can occur if the machine
  # is not yet running or is too busy to handle the request, so these exceptions
  # are automatically retried regardless of the retry value. Typically
  # callers set this to false to catch 'Connection Refused' exceptions or
  # the like. Finally, the caller must provide a block of
  # code that indicates the SOAP call to make: this is really all that differs
  # between the calling methods. The result of the block is returned to the
  # caller. 
  def make_call(time, retry_on_except, callr, ok_to_fail=false)
    refused_count = 0
    max = 5

    begin
      Timeout::timeout(time) {
        yield if block_given?
      }
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      if refused_count > max
        return false if ok_to_fail
        raise FailedNodeException.new("Connection was refused. Is the " +
          "AppController running?")
      else
        refused_count += 1
        Kernel.sleep(1)
        retry
      end
    rescue Timeout::Error
      return false if ok_to_fail
      retry
    rescue OpenSSL::SSL::SSLError, NotImplementedError, Errno::EPIPE, Errno::ECONNRESET, SOAP::EmptyResponseError
      retry
    rescue Exception => except
      if retry_on_except
        retry
      else
        trace = except.backtrace.join("\n")
        HelperFunctions.log_and_crash("[#{callr}] We saw an unexpected error" +
          " of the type #{except.class} with the following message:\n" +
          "#{except}, with trace: #{trace}")
      end
    end
  end


  def get_userappserver_ip(verbose_level="low") 
    userappserver_ip, status, state, new_state = "", "", "", ""
    loop {
      status = get_status()

      new_state = status.scan(/Current State: ([\w\s\d\.,]+)\n/).flatten.to_s.chomp
      if verbose_level == "high" and new_state != state
        puts new_state
        state = new_state
      end
    
      if status == "false: bad secret"
        HelperFunctions.log_and_crash("\nWe were unable to verify your " +
          "secret key with the head node specified in your locations " +
          "file. Are you sure you have the correct secret key and locations " +
          "file?\n\nSecret provided: [#{@secret}]\nHead node IP address: " +
          "[#{@ip}]\n")
      end
        
      if status =~ /Database is at (#{IP_OR_FQDN})/ and $1 != "not-up-yet"
        userappserver_ip = $1
        break
      end
      
      sleep(10)
    }
    
    return userappserver_ip
  end

  def set_parameters(locations, creds, apps_to_start)
    result = ""
    make_call(10, ABORT_ON_FAIL, "set_parameters") { 
      result = conn.set_parameters(locations, creds, apps_to_start, @secret)
    }  
    HelperFunctions.log_and_crash(result) if result =~ /Error:/
  end

  def set_apps(app_names)
    result = ""
    make_call(10, ABORT_ON_FAIL, "set_apps") { 
      result = conn.set_apps(app_names, @secret)
    }  
    HelperFunctions.log_and_crash(result) if result =~ /Error:/
  end

  def status(print_output=true)
    status = get_status()
         
    if print_output
      puts "Status of node at #{ip}:"
      puts "#{status}"
    end

    return status
  end

  def get_status(ok_to_fail=false)
    if !HelperFunctions.is_port_open?(@ip, 17443)
      if ok_to_fail
        return false
      else
        HelperFunctions.log_and_crash("AppController at #{@ip} is not running")
      end
    end

    make_call(10, !ok_to_fail, "get_status", ok_to_fail) { 
      @conn.status(@secret) 
    }
  end

  def get_stats(ok_to_fail=false)
    make_call(10, !ok_to_fail, "get_stats", ok_to_fail) { @conn.get_stats(@secret) }
  end

  def stop_app(app_name)
    make_call(30, RETRY_ON_FAIL, "stop_app") { @conn.stop_app(app_name, @secret) }
  end
  
  def update(app_names)
    make_call(30, RETRY_ON_FAIL, "update") { @conn.update(app_names, @secret) }
  end

  def is_done_initializing?()
    make_call(30, RETRY_ON_FAIL, "is_done_initializing") { @conn.is_done_initializing(@secret) }
  end

  def is_done_loading?()
    make_call(30, RETRY_ON_FAIL, "is_done_loading") { @conn.is_done_loading(@secret) }
  end
 
  def get_all_public_ips()
    make_call(30, RETRY_ON_FAIL, "get_all_public_ips") { @conn.get_all_public_ips(@secret) }
  end

  def add_role(role)
    make_call(NO_TIMEOUT, RETRY_ON_FAIL, "add_role") { @conn.add_role(role, @secret) }
  end

  # CGB - removed timeout here - removing cassandra slave requires it to port
  # the data it owns to somebody else, which takes ~30 seconds in the trivial
  # case
  def remove_role(role)
    make_call(NO_TIMEOUT, RETRY_ON_FAIL, "remove_role") { @conn.remove_role(role, @secret) }
  end

  def wait_for_node_to_be(new_roles)
    roles = new_roles.split(":")

    loop {
      ready = true
      status = get_status
      Djinn.log_debug("ACC: Node at #{@ip} said [#{status}]")
      roles.each { |role|
        if status =~ /#{role}/
          Djinn.log_debug("ACC: Node is #{role}")
        else
          ready = false
          Djinn.log_debug("ACC: Node is not yet #{role}")
        end
      }

      break if ready      
    }

    Djinn.log_debug("ACC: Node at #{@ip} is now #{new_roles}")
    return
  end

  def get_queues_in_use()
    make_call(NO_TIMEOUT, RETRY_ON_FAIL, "get_queues_in_use") { 
      @conn.get_queues_in_use(@secret)
    }
  end

  # Tells an AppController that it needs to restart one or more Google App
  # Engine applications.
  #
  # Args:
  #   app_names: An Array of Strings, where each String is an appid
  #     corresponding to an application that needs to be restarted.
  def set_apps_to_restart(app_names)
    make_call(NO_TIMEOUT, RETRY_ON_FAIL, "set_apps_to_restart") {
      @conn.set_apps_to_restart(app_names, @secret)
    }
  end

  # Tells an AppController to route HAProxy traffic to the given location.
  #
  # Args:
  #   app_id: A String that identifies the application that runs the new
  #     AppServer.
  #   ip: A String that identifies the private IP address where the new
  #     AppServer runs.
  #   port: A Fixnum that identifies the port where the new AppServer runs at
  #     ip.
  #   secret: A String that is used to authenticate the caller.
  def add_appserver_to_haproxy(app_id, ip, port)
    make_call(NO_TIMEOUT, RETRY_ON_FAIL, "add_appserver_to_haproxy") {
      @conn.add_appserver_to_haproxy(app_id, ip, port, @secret)
    }
  end

  # Tells an AppController to no longer route HAProxy traffic to the given
  # location.
  #
  # Args:
  #   app_id: A String that identifies the application that runs the AppServer
  #     to remove.
  #   ip: A String that identifies the private IP address where the AppServer
  #     to remove runs.
  #   port: A Fixnum that identifies the port where the AppServer was running.
  #   secret: A String that is used to authenticate the caller.
  def remove_appserver_from_haproxy(app_id, ip, port)
    make_call(NO_TIMEOUT, RETRY_ON_FAIL, "remove_appserver_from_haproxy") {
      @conn.remove_appserver_from_haproxy(app_id, ip, port, @secret)
    }
  end


  def add_appserver_process(app_id)
    make_call(NO_TIMEOUT, RETRY_ON_FAIL, "add_appserver_process") {
      @conn.add_appserver_process(app_id, @secret)
    }
  end

  def remove_appserver_process(app_id)
    make_call(NO_TIMEOUT, RETRY_ON_FAIL, "remove_appserver_process") {
      @conn.remove_appserver_process(app_id, @secret)
    }
  end

end
