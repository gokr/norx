import os

import norx/[incl, config, param, module, event, clock, memory]

template init*(body: untyped): untyped {.dirty.} =
  proc initProc(): orxSTATUS {.cdecl.} = body

template run*(body: untyped): untyped {.dirty.} =
  proc runProc(): orxSTATUS {.cdecl.} = body

template exit*(body: untyped) {.dirty.} =
  proc exitProc() {.cdecl.} = body

template bootstrap*(body: untyped): untyped {.dirty.} =
  proc bootstrapProc(): orxSTATUS {.cdecl.} = body

template execute*() {.dirty.} =
  execute(initProc, runProc, exitProc, bootstrapProc)

when not defined(PLUGIN):
  ## Should stop execution by default event handling?
  var sbStopByEvent* = false

  ##  Orx default basic event handler
  ##  @param[in]   pstEvent                     Sent event
  ##  @return      orxSTATUS_SUCCESS if handled / orxSTATUS_FAILURE otherwise
  proc orx_DefaultEventHandler*(pstEvent: ptr orxEVENT): orxSTATUS {.cdecl.} =
    ##  Checks
    assert(pstEvent.eType == orxEVENT_TYPE_SYSTEM)
    #echo "pstEvent.eType: " & $pstEvent.eType
    #echo "pstEvent.eID: " & $pstEvent.eID
    ##  Depending on event ID
    case pstEvent.eID:
      of ord(orxSYSTEM_EVENT_CLOSE):
        ##  Updates status
        sbStopByEvent = true
      else:
        discard
    return orxSTATUS_SUCCESS

  ## Default main setup (module dependencies)
  proc orx_MainSetup*() {.cdecl.} =
    ##  Adds module dependencies
    addDependency(orxMODULE_ID_MAIN, orxMODULE_ID_PARAM)
    addDependency(orxMODULE_ID_MAIN, orxMODULE_ID_CLOCK)
    addDependency(orxMODULE_ID_MAIN, orxMODULE_ID_CONFIG)
    addDependency(orxMODULE_ID_MAIN, orxMODULE_ID_INPUT)
    addDependency(orxMODULE_ID_MAIN, orxMODULE_ID_EVENT)
    addDependency(orxMODULE_ID_MAIN, orxMODULE_ID_FILE)
    addDependency(orxMODULE_ID_MAIN, orxMODULE_ID_LOCALE)
    addDependency(orxMODULE_ID_MAIN, orxMODULE_ID_PLUGIN)
    addDependency(orxMODULE_ID_MAIN, orxMODULE_ID_OBJECT)
    addDependency(orxMODULE_ID_MAIN, orxMODULE_ID_RENDER)
    addOptionalDependency(orxMODULE_ID_MAIN, orxMODULE_ID_CONSOLE)
    addOptionalDependency(orxMODULE_ID_MAIN, orxMODULE_ID_PROFILER)
    addOptionalDependency(orxMODULE_ID_MAIN, orxMODULE_ID_SCREENSHOT)

  when defined(iOS):
    discard
  else:
    when defined(Android) or defined(ANDROID_NATIVE):
      import
        main/orxAndroid

      ## * Orx main execution function
      ##  @param[in]   _u32NbParams                  Main function parameters number (argc)
      ##  @param[in]   _azParams                     Main function parameter list (argv)
      ##  @param[in]   _pfnInit                      Main init function (should init all the main stuff and register the main event handler to override the default one)
      ##  @param[in]   _pfnRun                       Main run function (will be called once per frame, should return orxSTATUS_SUCCESS to continue processing)
      ##  @param[in]   _pfnExit                      Main exit function (should clean all the main stuff)
      ##
      proc orx_Execute*(u32NbParams: orxU32; azParams: cstringArray;
                       pfnInit: orxMODULE_INIT_FUNCTION;
                       pfnRun: orxMODULE_RUN_FUNCTION;
                       pfnExit: orxMODULE_EXIT_FUNCTION) {.inline, cdecl.} =
        ##  Inits the Debug System
        orxDEBUG_INIT_MACRO()
        ##  Checks
        assert(pfnRun != nil)
        ##  Registers main module
        moduleRegister(orxMODULE_ID_MAIN, "MAIN", orx_MainSetup, pfnInit, pfnExit)
        ##  Sends the command line arguments to orxParam module
        if setArgs(u32NbParams, azParams) != orxSTATUS_FAILURE:
          ##  Sets thread callbacks
          setCallbacks(orxAndroid_JNI_SetupThread, nil, nil)
          ##  Inits the engine
          if orxModule_Init(orxMODULE_ID_MAIN) != orxSTATUS_FAILURE:
            var stPayload: orxSYSTEM_EVENT_PAYLOAD
            var
              eClockStatus: orxSTATUS
              eMainStatus: orxSTATUS
            ##  Registers default event handler
            addHandler(orxEVENT_TYPE_SYSTEM, orx_DefaultEventHandler)
            ##  Clears payload
            zero(addr(stPayload), sizeof((orxSYSTEM_EVENT_PAYLOAD)))
            ##  Main loop
            var bStop = false
            sbStopByEvent = false
            while not bStop:
              orxAndroid_PumpEvents()
              ##  Sends frame start event
              orxEVENT_SEND_MACRO(orxEVENT_TYPE_SYSTEM,
                            orxSYSTEM_EVENT_GAME_LOOP_START, nil, nil,
                            addr(stPayload))
              ##  Runs the engine
              eMainStatus = pfnRun()
              ##  Updates clock system
              eClockStatus = orxClock_Update()
              ##  Sends frame stop event
              orxEVENT_SEND_MACRO(orxEVENT_TYPE_SYSTEM, orxSYSTEM_EVENT_GAME_LOOP_STOP,
                            nil, nil, addr(stPayload))
              ##  Updates frame count
              inc(stPayload.u32FrameCount)
              bStop = (sbStopByEvent or (eMainStatus == orxSTATUS_FAILURE) or (eClockStatus == orxSTATUS_FAILURE))
          orxEvent_RemoveHandler(orxEVENT_TYPE_SYSTEM, orx_DefaultEventHandler)
          ##  Exits from engine
          orxModule_Exit(orxMODULE_ID_MAIN)
        orxDEBUG_EXIT_MACRO()

    else:
      ## * Orx main execution function
      ##  @param[in]   _u32NbParams                  Main function parameters number (argc)
      ##  @param[in]   _azParams                     Main function parameter list (argv)
      ##  @param[in]   _pfnInit                      Main init function (should init all the main stuff and register the main event handler to override the default one)
      ##  @param[in]   _pfnRun                       Main run function (will be called once per frame, should return orxSTATUS_SUCCESS to continue processing)
      ##  @param[in]   _pfnExit                      Main exit function (should clean all the main stuff)
      ##
      proc execute*(initProc: proc(): orxSTATUS {.cdecl.};
                    runProc: proc(): orxSTATUS {.cdecl.};
                    exitProc: proc() {.cdecl.};
                    bootstrapProc: proc(): orxSTATUS {.cdecl.}) {.inline} =
        discard setBootstrap(bootstrapProc)
        ## Inits the Debug System
        orxDEBUG_INIT_MACRO()
        ## Checks
        assert(runProc != nil)
        ##  Registers main module
        register(orxMODULE_ID_MAIN, "MAIN", orx_MainSetup, initProc, exitProc)
        # Hack to produce C style argc/argv to pass on
        var argc = paramCount()
        var nargv = newSeq[string](argc + 1)
        nargv[0] = getAppFilename()  # Better than paramStr(0)
        var x = 1
        while x <= argc:
          nargv[x] = paramStr(x)
          inc(x)
        var argv: cstringArray = nargv.allocCStringArray()
        inc(argc)
        ##  Sends the command line arguments to orxParam module
        if setArgs(argc.orxU32, argv) != orxSTATUS_FAILURE:
          ##  Inits the engine
          if moduleInit(orxMODULE_ID_MAIN) != orxSTATUS_FAILURE:
            var
              stPayload: orxSYSTEM_EVENT_PAYLOAD
              eClockStatus: orxSTATUS
              eMainStatus: orxSTATUS
            ##  Registers default event handler
            var st = addHandler(orxEVENT_TYPE_SYSTEM, orx_DefaultEventHandler)
            ##  Clears payload
            discard zero(addr(stPayload), sizeof(orxSYSTEM_EVENT_PAYLOAD).orxU32)
            ##  Main loop
            var bStop = false
            sbStopByEvent = false
            while not bStop:
              ##  Sends frame start event
              orxEVENT_SEND_MACRO(orxEVENT_TYPE_SYSTEM, orxSYSTEM_EVENT_GAME_LOOP_START, nil, nil, addr(stPayload))
              ##  Runs the engine
              eMainStatus = runProc()
              ##  Updates clock system
              eClockStatus = update()
              ##  Sends frame stop event
              orxEVENT_SEND_MACRO(orxEVENT_TYPE_SYSTEM, orxSYSTEM_EVENT_GAME_LOOP_STOP, nil, nil, addr(stPayload))
              ##  Updates frame count
              stPayload.u32FrameCount += 1
              bStop = (sbStopByEvent or (eMainStatus == orxSTATUS_FAILURE) or (eClockStatus == orxSTATUS_FAILURE))
          discard removeHandler(orxEVENT_TYPE_SYSTEM, cast[orxEVENT_HANDLER](orx_DefaultEventHandler))
          ##  Exits from engine
          moduleExit(orxMODULE_ID_MAIN)
        orxDEBUG_EXIT_MACRO()