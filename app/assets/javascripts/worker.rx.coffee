
#
# Global struct to hold app data
window.WorkerData =
  UUID: null
  name: ''
  currentChatId: 0
  providers: []
  Worker: null
  Notification:
    slot: {}
    nextid: 0
  pending: []



#
# CometSocket class
class CometSocket
  constructor: (uuid, token, domain) ->
    @url = uuid
    console.log("CometSocket calling create")
    @$frame = $('#comet')
    if( this.$frame.size() == 0 )
      #$('body').append('<iframe id="comet" src="http://'+domain+':9009/ws/comet/'+uuid+'/'+token+'/'+WorkerData.currentChatId+'" style="visibility: hidden"></iframe>')
      $('body').append('<iframe id="comet" src="https://'+domain+'/ws/comet/'+uuid+'/'+token+'/'+WorkerData.currentChatId+'" style="visibility: hidden"></iframe>')
      @.$frame = $('#comet')
  send: (data) ->
    console.log("CometSocket SEND")
    data.time = new Date().getTime()
    data.rand = Math.random()
    $.post( "/ws/comet/send/"+WorkerData.currentChatId, { data: data }
      ,->
        console.log('comet send success')
      , ->
        console.log('comet send fail')
    )

#
# Worker Class
class window.WalkaboutWorker
  constructor: (uuid, username, token, chatid, $rootScope, domain) ->
    @uuid = uuid
    @token = token
    @domain = domain || self.location.hostname
    @$rootScope = $rootScope
    @username = username
    @isConnected = false
    @retrySocket = true
    @retryTimeout = 5000
    @subjects = {}
    @controllerOps =
      uuid: => parseInt(@uuid)
      username: -> @username
      subject: (subject) => @subject(subject)
      onNext: (data) => @onNext(data)
      broadcast: (evn, args) =>
        @$rootScope.$broadcast(evn, args)
      verifyConnection: =>
        if( !@isConnected && @retrySocket)
          @connect()
    @connect()
  onSocketClose: null       # callback
  socketRetry: ->
    @isConnected = false
    @retrySocket = true
    console.log('ws: worker socket CLOSED.  trying to reconnect')
    @$rootScope.page.error = 'Connection problem.  Standby while we try to reconnect.'
    setTimeout(=>
      @$rootScope.$apply()
    ,0)
    @retryTimeout = @retryTimeout * 2
    if( @onSocketClose? )
      @onSocketClose()
    setTimeout(=>
      @connect()
    ,@retryTimeout)

  connect: -> # This gets implemented in Implementing class See WalkaboutSocketWorker

  onNext: (data) ->

  end: ->

  subject: (subject) ->
    if( !@subjects[subject] )
      @subjects[subject] = new Rx.Subject()
      #@wsObservable.filter( (s) ->s.slot == subject ).subscribe(rxSubject)
      @wsSubject.filter((s) ->s.slot == subject ).subscribe(@subjects[subject])
    @subjects[subject]

  replaySubject:(subject) ->
    if( !@subjects[subject] )
      @subjects[subject] = new Rx.ReplaySubject()
      #@wsObservable.filter( (s) ->s.slot == subject ).subscribe(rxSubject)
      @wsSubject.filter((s) ->s.slot == subject ).subscribe(@subjects[subject])
    @subjects[subject]

  broadcast: (evn, args) ->
    @$rootScope.$broadcast(evn, args)

# end of worker class...




#
# WalkaboutSocketWorker
class window.WalkaboutSocketWorker extends WalkaboutWorker
  constructor: (uuid, username, token, chatid, $rootScope, domain) ->
    super(uuid, username, token, chatid, $rootScope, domain)
  connect: ->
    if( !@isConnected && @retrySocket)
      @retrySocket = false
      # this is a shit test for android stock.. but seems like the best out there..
      # http://stackoverflow.com/questions/14403766/how-to-detect-the-stock-android-browser
      nua = navigator.userAgent;
      isAndroidStock = (nua.indexOf('Android ') > -1 && nua.indexOf('Chrome') == -1 && nua.indexOf('Firefox') == -1 && nua.indexOf('Opera') == -1)
      if isAndroidStock || !window.WebSocket
        @ws = new CometSocket(@uuid, @token)
        ws = @ws;
        setTimeout( ->
          ws.onopen({})  # fire the open event..
        ,2500)
      else
        # TODO: for mobile web clients.. will be need a "ping" the same as we have to for the native client
        #this.ws = new WebSocket('wss://'+@domain+':9009/api/'+this.uuid+'/'+this.token+'/'+WorkerData.currentChatId);
        try
          @ws = new WebSocket('wss://'+@domain+'/api/'+@uuid+'/'+@token+'/'+WorkerData.currentChatId);
        catch e
          @socketRetry()

      @ws.onopen = (evt) =>
        console.log('worker websocket CONNECT.')
        @$rootScope.page.error = ''   #clear any errors
        setTimeout(=>
          @$rootScope.$apply()
        ,0)
        @retryTimeout = 5000
        setTimeout(=>
          @isConnected = true
          @retrySocket = true
          console.log('Setting isConnected = ' + @isConnected)
          # get a list of our friends
          actors = []
          # Send any pending request..
          console.log("Sending " + WorkerData.pending.length + " items from queue")
          for p of WorkerData.pending
            WorkerData.Worker.onNext( WorkerData.pending[p] )
          WorkerData.pending = []    # clear the queue
        ,0)
      @ws.onerror = (evt) =>
        @socketRetry()

      @ws.onclose = (evt) =>
        @socketRetry()
      #alert('You have been disconnected.  Please refresh you browser.')

      ws = @ws
      @wsObservable = Rx.Observable.create( (obs) ->
        # iframe posts back to here...
        window.cometMessage = (data) ->
          console.log('got a comet msg ',data)
          #obs.onNext(JSON.parse(data))
          obs.onNext(data)
        ws.onmessage = (data) ->
          #console.log('ws: onmessage ' + data.data)
          obs.onNext(JSON.parse(data.data))
        ws.onerror = (err) ->
          console.log('ws: Worker socket ERROR:', err)
        # TODO: propagate the exception onto the observable here?
        ->
          console.log('@wsObservable dispose')
      )
      @wsSubject = new Rx.Subject() if not @wsSubject?
      @wsObservable.subscribe(@wsSubject)

  onNext: (data) ->
    dataStr = JSON.stringify(data)
    console.log('ws: Send: ' + dataStr)
    if( @isConnected )
      @ws.send( dataStr )
    else
      WorkerData.pending.push(data)
  end: ->
    WorkerData.Worker.ws.close()






















