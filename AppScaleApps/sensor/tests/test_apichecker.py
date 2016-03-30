#!/usr/bin/env python
""" Testing for high level API checker. """
import json
import os
import sys
import unittest

from flexmock import flexmock

# Include these paths to get webapp2.
sys.path.append(os.path.join(os.path.dirname(__file__), "../../google_appengine/lib/webob-1.2.3"))
sys.path.append(os.path.join(os.path.dirname(__file__), "../../google_appengine/lib/webapp2-2.5.2/"))
import webapp2

sys.path.append(os.path.join(os.path.dirname(__file__), "../"))
import apichecker

sys.path.append(os.path.join(os.path.dirname(__file__), "../../google_appengine/"))
from google.appengine.api import urlfetch

from common import constants
from common import util
import settings

class FakeRunner:
  def __init__(self, uuid):
    self.uuid = uuid
  def run(self):
    return {'fake':'value'}
  def cleanup(self):
    return

class TestApiChecker(unittest.TestCase):
  def test_get_result(self):
    flexmock(apichecker).should_receive('get_runner_constructor').and_return(FakeRunner)
    uuid = 'myuuid'

    expected = {constants.ApiTags.DATA: {uuid: {"Memcache": {'fake':'value'}}},
      constants.ApiTags.USER_ID: settings.USER_ID,
      constants.ApiTags.APP_ID: settings.APP_ID,
      constants.ApiTags.API_KEY: settings.API_KEY}
    self.assertEquals(json.dumps(expected), apichecker.get_result('Memcache', uuid))

    expected = {constants.ApiTags.DATA: {uuid: {"DB": {'fake':'value'}}},
      constants.ApiTags.USER_ID: settings.USER_ID,
      constants.ApiTags.APP_ID: settings.APP_ID,
      constants.ApiTags.API_KEY: settings.API_KEY}
    self.assertEquals(json.dumps(expected), apichecker.get_result('DB', uuid))

    expected = {constants.ApiTags.DATA: {uuid: {"Urlfetch": {'fake':'value'}}},
      constants.ApiTags.USER_ID: settings.USER_ID,
      constants.ApiTags.APP_ID: settings.APP_ID,
      constants.ApiTags.API_KEY: settings.API_KEY}
    self.assertEquals(json.dumps(expected), apichecker.get_result('Urlfetch', uuid))


  def test_post_results(self):
    result = flexmock(status_code=constants.HTTP_OK)
    flexmock(urlfetch).should_receive("fetch").twice().and_return(result)
    apichecker.post_results("fakedata") 

class TestHandlers(unittest.TestCase):
  def test_allchecker(self):
    request = webapp2.Request.blank('/health/all')
    flexmock(apichecker).should_receive('get_runner_constructor').and_return(FakeRunner)
    flexmock(apichecker).should_receive('post_results').and_return()
    uuid = 'myuuid'
    flexmock(util).should_receive('get_uuid').and_return(uuid)
    response = request.get_response(apichecker.APP)

    expected = {constants.ApiTags.DATA: {uuid: 
        {"Urlfetch": {'fake': 'value'}, 
        'Memcache': {'fake': 'value'}, 
        'DB': {'fake': 'value'}}},
      constants.ApiTags.USER_ID: settings.USER_ID,
      constants.ApiTags.APP_ID: settings.APP_ID,
      constants.ApiTags.API_KEY: settings.API_KEY}

    self.assertEqual(response.status_int, constants.HTTP_OK)
    self.assertEqual(json.loads(response.body), expected)

  def test_dbchecker(self):
    request = webapp2.Request.blank('/health/db')
    flexmock(apichecker).should_receive('get_result').and_return('blah')
    flexmock(apichecker).should_receive('post_results').and_return()
    flexmock(util).should_receive('get_uuid').and_return(123)
    response = request.get_response(apichecker.APP)
    expected = "blah"
    self.assertEqual(response.status_int, constants.HTTP_OK)
    self.assertEqual(response.body, expected)

  def test_memcachechecker(self):
    request = webapp2.Request.blank('/health/memcache')
    flexmock(apichecker).should_receive('get_result').and_return('blah')
    flexmock(apichecker).should_receive('post_results').and_return()
    flexmock(util).should_receive('get_uuid').and_return(123)
    response = request.get_response(apichecker.APP)
    expected = "blah"
    self.assertEqual(response.status_int, constants.HTTP_OK)
    self.assertEqual(response.body, expected)

  def test_urlfetch(self):
    request = webapp2.Request.blank('/health/urlfetch')
    flexmock(apichecker).should_receive('get_result').and_return('blah')
    flexmock(apichecker).should_receive('post_results').and_return()
    flexmock(util).should_receive('get_uuid').and_return(123)
    response = request.get_response(apichecker.APP)
    expected = "blah"
    self.assertEqual(response.status_int, constants.HTTP_OK)
    self.assertEqual(response.body, expected)
