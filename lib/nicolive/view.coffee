request= require 'request'
cheerio= require 'cheerio'

net= require 'net'

chalk= require 'chalk'
h1= chalk.underline.magenta

{url,resultcode}= require '../api'

module.exports= (live_id,args...,callback)->
  options= args[0] ? {}

  @getPlayerStatus live_id,options,(error,playerStatus)=>
    return callback error if error?
    @playerStatus= playerStatus
    {
      port,addr
      thread,version,res_from
      comment_count
      user_id,premium,mail
    }= playerStatus

    console.log h1('Request to'),url.comment+thread if options.verbose

    @viewer.destroy() if @viewer?
    @viewer= net.connect port,addr
    @viewer.on 'connect',=>
      comment= cheerio '<thread />'
      comment.attr {thread,version,res_from}
      comment.options.xmlMode= on

      @viewer.write comment.toString()+'\0'
      @viewer.setEncoding 'utf-8'

    chunks= ''
    @viewer.on 'data',(buffer)=>
      chunk= buffer.toString()
      chunks+= chunk
      return unless chunk.match /\0$/

      console.log chunks if options.verbose
      data= cheerio '<data>'+chunks+'</data>'
      chunks= ''

      resultcodeValue= data.find('thread').attr 'resultcode'
      if resultcodeValue?.length
        {code,description}= resultcode[resultcodeValue]
        ticket= data.find('thread').attr 'ticket'

        console.log h1('Resultcode '+resultcodeValue+':'),code,description unless process.env.JASMINETEA_ID?
        console.log h1('Chat attrs:'),{thread,ticket,mail,user_id,premium} if options.verbose and resultcodeValue is '0'
        
        @attrs= {thread,ticket,mail,user_id,premium}
        @viewer.emit 'handshaked',@attrs if resultcodeValue is '0'
        @viewer.emit 'error',data.find('thread').toString() if resultcodeValue isnt '0'

      comments= data.find 'chat'
      for comment in comments
        element= cheerio comment

        console.log element.toString() if options.verbose

        comment=
          attr: element.attr()
          text: element.text()
          usericon: url.usericonEmptyURL

        {anonymity,user_id}= comment.attr
        unless anonymity?
          comment.usericon= url.usericonURL+user_id.slice(0,2)+'/'+user_id+'.jpg' if user_id

        @viewer.emit 'comment',comment
        @playerStatus.comment_count= comment.attr.no if comment.attr.no>@playerStatus.comment_count

    if options.verbose
      console.log h1('Connect to'),"""
      http://#{addr}:#{port}/api/thread?thread=#{thread}&version=#{version}&res_from=#{res_from}
      """
      console.log h1('Or  static'),"""
      http://#{addr}:#{port-2725}/api/thread?thread=#{thread}&version=#{version}&res_from=#{res_from}
      """

      @viewer.on 'timeout',-> console.log h1('Timeout'),arguments
      @viewer.on 'lookup',-> console.log h1('Lookup'),arguments
      @viewer.on 'error',-> console.log h1('Error'),arguments

    callback null,@viewer