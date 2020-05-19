# datHandler contains...

$.holdReady true

_ = require 'underscore'

module.exports = datHandler = {}

# we save details of each plugin
pluginRoutes = {}
pluginPages = {}
factories = []

# a list of default wiki pages that the client holds
defaultPages = []


clientOrigin = ''
wikiOrigin = ''


datHandler.archive = beaker.hyperdrive.drive(window.location.origin)

datHandler.pluginPages = pluginPages
datHandler.pluginRoutes = pluginRoutes
datHandler.factories = factories
datHandler.defaultPages = defaultPages
datHandler.clientOrigin = clientOrigin

datHandler.init = init = () ->

  # load configuration for plugins
  loadPluginData = () ->
    # fetch plugin defaults
    fetchDefaultPlugins = () ->
      url = clientOrigin + "/plugins.json"
      fetch(url)
      .then (response) ->
        return response.json()

    fetchLocalPlugins = () ->
      try
        data = await datHandler.archive.readFile('/plugins.json')
        parsedData = JSON.parse(data)
      catch error
        console.log "Fetch Local Plugins:", error
        parsedData = {}
      return parsedData

    defaultPlugins = await fetchDefaultPlugins()
    _.each defaultPlugins, (pluginURL, plugin) ->
      pluginRoutes[plugin] = pluginURL
    # allow wiki site to load/override plugins
    localPlugins = await fetchLocalPlugins()
    _.each localPlugins, (pluginURL, plugin) ->
      pluginRoutes[plugin] = pluginURL


  # build a list of plugin pages
  buildPluginPageList = () ->
    _.each pluginRoutes, (pluginURL, plugin) ->
      url = new URL(pluginURL)
      datOrigin = url.origin
      pluginPath = url.pathname
      pluginArchive = beaker.hyperdrive.drive(datOrigin)
      try
        pages = await pluginArchive.readdir(pluginPath + "/pages")
      catch error
        pages = []
      _.each pages, (page) ->
        # we are only interested in page files
        pluginPages[page] = {url: pluginURL, plugin: plugin} if page.endsWith('.json')

  buildFactoriesList = () ->
    _.each pluginRoutes, (pluginURL, plugin) ->
      url = pluginURL + "/factory.json"
      fetch(url)
      .then (response) ->
        return response.json()
      .then (factoryJson) ->
        factories.push factoryJson
      .catch (err) ->
        console.log "No factory details for #{plugin}"

  buildDefaultPageList = () ->
    clientArchive = beaker.hyperdrive.drive(clientOrigin)
    try
      pages = await clientArchive.readdir("/pages", {includeStats: true})
    catch error
      pages = []
    pages = pages.filter (page) -> page.stat.isFile() and page.name.endsWith('.json')
    _.each pages, (page) ->
      defaultPages.push page.name

  clientOrigin = new URL(document.currentScript.src).origin
  wikiOrigin = window.location.origin


  await loadPluginData()

  await buildPluginPageList()

  await buildFactoriesList()

  await buildDefaultPageList()

  $.holdReady false

init()
