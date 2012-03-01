###
Kache - a cross-browser LocalStorage API
https://github.com/leveille/kache
Version: {{version}}
###
root = exports ? this

isNumber =(n) ->
  typeof n == 'number' && isFinite(n)

isExpired =(item) ->
  item and item.e and item.e < time()

noop =->

time =->
  +new Date()

count =(obj) ->
  _count = 0
  for own key, value of obj
    _count++
  _count

DefaultKacheConfig = {
  enabled: false,
  defaultTimeout: 0, # Cache objects will not timeout
  namespacePrefix: '',
  Timeouts: {}
}

if root.KacheConfig
  root.KacheConfig.enabled ?= DefaultKacheConfig.enabled
  root.KacheConfig.defaultTimeout ?= DefaultKacheConfig.defaultTimeout
  root.KacheConfig.namespacePrefix ?= DefaultKacheConfig.namespacePrefix
  root.KacheConfig.Timeouts ?= DefaultKacheConfig.Timeouts
else
  root.KacheConfig = DefaultKacheConfig

# Yes, Log and Module borrowed from Spine
Log =
  trace: true
  logPrefix: "(Kache)"
  log: (args...) ->
    return unless @trace
    return if typeof console is "undefined"
    if @logPrefix then args.unshift(@logPrefix)
    console.log(args...)
    @

moduleKeywords = ["included", "extended"]
class Module
  @include: (obj) ->
    throw("include(obj) requires obj") unless obj
    for key, value of obj when key not in moduleKeywords
      @::[key] = value

    included = obj.included
    included.apply(this) if included
    @

  @extend: (obj) ->
    throw("extend(obj) requires obj") unless obj
    for key, value of obj when key not in moduleKeywords
      @[key] = value

    extended = obj.extended
    extended.apply(this) if extended
    @

  @proxy: (func) ->
    => func.apply(@, arguments)

  proxy: (func) ->
    => func.apply(@, arguments)

class Store extends Module
  @include Log
  constructor: (kwargs) ->
    @load @attrs if @attrs
    @.logPrefix = kwargs.logPrefix if kwargs.logPrefix
    @namespace = root.KacheConfig.namespacePrefix + '#' + @namespace if root.KacheConfig.namespacePrefix and @disablePrefix != true

    throw 'Cannot load cache store' if not kwargs['load']
    @_ = kwargs.load()
    throw 'Invalid Cache Instance' if not @_

    if root.KacheConfig
      if root.KacheConfig.Timeouts and root.KacheConfig.Timeouts[@namespace]
        timeout = root.KacheConfig.Timeouts[@namespace]
      else if root.KacheConfig.defaultTimeout
        timeout = root.KacheConfig.defaultTimeout
      else
        timeout = 0
    @timeout ?= timeout

  clear: ->
    @_ = {}
    @writeThrough()
    @

  clearExpired: (k) ->
    if isExpired @_[k]
      @remove k
    @

  clearExpireds: ->
    for key, item of @_
      @clearExpired key
    @

  count: ->
    @clearExpireds()
    count(@_)

  dump: ->
    @.log @_
    @

  enabled: ->
    throw "NotImplemented exception"

  error: (e)->
    @.log e

  get: (k) ->
    return unless !!@enabled()
    @clearExpired k
    if @_[k] and @_[k].v
      @_[k].v

  load: (atts) ->
    for key, value of atts
      @[key] = value

  remove: (k) ->
    delete @_[k]
    @writeThrough()
    @

  set: (key, value, timeout) ->
    @clearExpireds()
    timeout ?= @timeout
    if isNumber(timeout) and timeout != 0
      expires = time() + timeout
    try
      @_[key] =
        v: value,
        e: expires or 0,
        t: timeout
      @writeThrough()
    catch e
      @error(e)
      value = null
    value

  toString: ->
    "#{@namespace} : #{@timeout}"

  writeThrough: ->
    noop()
    @

class MemoryStore extends Store
  root._kache ?=
    _kache =
      store: {},
      enabled: root.KacheConfig.enabled
  @kache: root._kache

  @clearExpireds: ->
    for own key, value of @store
      obj = @store[key]
      for ns, item of obj
        if isExpired item
          hasDeleted = true
          delete item
      if hasDeleted
        @store[key] = obj
        if count(@store[key]) == 0
          delete @store[key]
    @

  @clearStore: ->
    @store = {}
    @

  @disable: ->
    root._kache.enabled = false
    @

  @enable: ->
    root._kache.enabled = true
    @

  @isEnabled: ->
    !!((root._kache and root._kache.enabled) \
        or (root.KacheConfig and root.KacheConfig.enabled) \
        or false)

  @validStore: ->
    true

  store: root._kache.store

  constructor: (@namespace, @timeout, @attrs) ->
    kwargs =
      'load' : @proxy -> @store[@namespace] ?= {}
      'logPrefix' : 'MemoryStore'
    super kwargs

  enabled: ->
    !!MemoryStore.isEnabled()

class LocalStore extends Store
  _enabled_key = '_kache_enabled'

  @clearStore: ->
    enabled = @isEnabled() if localStorage[_enabled_key] != undefined
    localStorage.clear()
    localStorage[_enabled_key] = enabled if enabled != undefined
    @

  @clearExpireds: ->
    for own key, value of @store
      for k, item of JSON.parse value
        if isExpired item
          hasDeleted = true
          delete item
        if hasDeleted
          if count(value) == 0
            delete value
            return
        value ?= {}
        @store[key] = JSON.stringify value
    @

  @enable: ->
    localStorage[_enabled_key] = 'true'
    @

  @disable: ->
    localStorage[_enabled_key] = 'false'
    @

  @isEnabled: ->
    !!((localStorage[_enabled_key] and localStorage[_enabled_key] == 'true') \
        or (root.KacheConfig and root.KacheConfig.enabled) \
        or false)

  @validStore: ->
    try
      !!localStorage
    catch error
      false

  store: localStorage

  constructor: (@namespace, @timeout, @attrs) ->
    if !LocalStore.validStore()
      throw 'LocalStorage is not a valid cache store'
    kwargs =
      'load' : @proxy -> JSON.parse @store[@namespace] or '{}'
      'logPrefix' : 'LocalStore'
    super kwargs

  enabled: ->
    !!LocalStore.isEnabled()

  error: (e)->
    if e == 'QUOTA_EXCEEDED_ERR'
      @.log 'QUOTA_EXCEEDED_ERR'
      @clearExpireds()
    else
      super e
    return

  writeThrough: ->
    @store[@namespace] = JSON.stringify @_
    @


DefaultStore =
  if LocalStore.validStore()
    LocalStore
  else
    MemoryStore

root.Kache = (namespace, timeout, atts) ->
  new DefaultStore(namespace, timeout, atts)

root.Kache.Local            = LocalStore
root.Kache.Memory           = MemoryStore

root.Kache.clearStore       = DefaultStore.clearStore
root.Kache.clearExpireds    = DefaultStore.clearExpireds
root.Kache.disable          = DefaultStore.disable
root.Kache.enable           = DefaultStore.enable
root.Kache.isEnabled        = DefaultStore.isEnabled
root.Kache.__version__      = '{{version}}'
