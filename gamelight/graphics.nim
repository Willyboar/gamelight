import sugar, math, tables, colors, os, options
from lenientops import `/`

const
  isCanvas = defined(js)

when isCanvas:
  import dom, jsconsole
  import canvasjs
  import base64
else:
  import strutils, os
  import sdl2/[ttf, image]
  import sdl2 except Point
  import chroma
import vec

when isCanvas:
  type
    PositionedElement = ref object
      originalLeft, originalTop: float
      originalFontSize: float
      originalWidth, originalHeight: float
      element: Element

type
  EventKind* = enum
    KeyDown, MouseButtonDown, MouseButtonUp, MouseMotion,
    FingerMotion, FingerUp, FingerDown, SizeChanged

  FileFormat* = enum
    FileFormatSVG

type
  Renderer2D* = ref object
    when isCanvas:
      canvas: EmbedElement
      context*: CanvasRenderingContext
      lastFrameUpdate: float
    else:
      window: WindowPtr
      sdlRenderer: RendererPtr
      events: array[EventKind, proc (evt: sdl2.Event)]
      scalingFactor: Point[float]
      translationFactor: Point[int]
      savedFactors: seq[(Point[float], Point[int])]
      currentPath: seq[Point[int]]
      fontCache: Table[(string, cint), FontPtr]
      lastFrameUpdate: uint64
      clippingMask: Option[Surface2D]
    preferredWidth: int
    preferredHeight: int
    rotation: float
    scaleToScreen: bool
    when isCanvas:
      positionedElements: seq[PositionedElement]
      images: Table[string, Image]
    else:
      texturesFromFile, texturesFromString: Table[string, TexturePtr]

  Surface2D* = ref object ## Off-screen rendering canvas.
    when isCanvas:
      canvas: EmbedElement
      context*: CanvasRenderingContext
    else:
      renderer2D: Renderer2D
      texture: TexturePtr
      scalingFactor: Point[float]
      translationFactor: Point[int]
      savedFactors: seq[(Point[float], Point[int])]
      currentPath: seq[Point[int]]
      preferredWidth: int
      preferredHeight: int

  Drawable2D* = Renderer2D or Surface2D

  TextMetrics* = object
    width*, height*: cint

type
  ImageAlignment* = enum
    Center, TopLeft

proc adjustPos[T](width, height: int, pos: Point[T], align: ImageAlignment): Point[T] =
  result = pos
  case align
  of Center:
    result = Point[T](
      x: T(pos.x.int - (width div 2)),
      y: T(pos.y.int - (height div 2))
    )
  of TopLeft:
    discard

when isCanvas:
  export KeyboardEvent, MouseEvent, TouchEvent
  type
    MouseButtonEvent* = MouseEvent
    MouseMotionEvent* = MouseEvent

  const
    positionedElementCssClass = "gamelight-graphics-element"

  proc getWidth(preferredWidth: int): int =
    if preferredWidth == -1:
      window.innerWidth
    else:
      preferredWidth

  proc getHeight(preferredHeight: int): int =
    if preferredHeight == -1:
      window.innerHeight
    else:
      preferredHeight

  template getScalingFactors() =
    let screenWidth {.inject.} = window.innerWidth
    let screenHeight {.inject.} = window.innerHeight
    let ratioX = screenWidth / renderer.canvas.width
    let ratioY = screenHeight / renderer.canvas.height

    # We also grab the current zoom ratio. This is necessary when the user
    # zooms accidentally, or the OS zooms for them (when keyboard shows up on
    # iOS for example)
    # Ref: http://stackoverflow.com/a/11797565/492186
    let zoomRatio = document.body.clientWidth / window.innerWidth

    let minRatio {.inject.} = min(ratioX, ratioY)
    let scaledWidth {.inject.} = renderer.canvas.width.float * minRatio
    let scaledHeight {.inject.} = renderer.canvas.height.float * minRatio

    let left {.inject.} = (screenWidth.float - scaledWidth) / 2
    let top {.inject.} = (screenHeight.float - scaledHeight) / 2

  proc scale*[T](renderer: Renderer2D, pos: Point[T]): Point[T] =
    ## Scales the specified ``Point[T]`` by the scaling factor, if the
    ## ``scaleToScreen`` option is enabled, otherwise just returns ``pos``.
    ##
    ## Note: This does not convert the point into screen coordinates, it assumes
    ## the point will be used on the canvas. So (0, 0) is the top of the canvas.
    if renderer.scaleToScreen:
      getScalingFactors()

      return (T(pos.x.float * minRatio),
              T(pos.y.float * minRatio))
    else:
      return pos

  proc resizeCanvas(renderer: Renderer2D) =
    renderer.canvas.width = getWidth(renderer.preferredWidth)

    renderer.canvas.height = getHeight(renderer.preferredHeight)

    if renderer.scaleToScreen:
      console.log("Scaling to screen")
      getScalingFactors()

      renderer.canvas.style.width = $scaledWidth & "px"
      renderer.canvas.style.height = $scaledHeight & "px"
      renderer.canvas.style.marginLeft = $left & "px"
      renderer.canvas.style.marginTop = $top & "px"

      # Ensure the parent container has the correct styles.
      renderer.canvas.parentNode.style.position = "absolute"
      renderer.canvas.parentNode.style.left = "0"
      renderer.canvas.parentNode.style.top = "0"
      renderer.canvas.parentNode.style.width = $screenWidth & "px"
      renderer.canvas.parentNode.style.height = $screenHeight & "px"
      renderer.canvas.parentNode.Element.classList.add("fullscreen")

      # Go through each element and adjust its position.
      for item in renderer.positionedElements:
        let element = item.element
        element.style.marginLeft =
          $(item.originalLeft * minRatio + left) & "px"
        element.style.marginTop =
          $(item.originalTop * minRatio + top) & "px"

        if item.originalFontSize > 0.0:
          element.style.fontSize = $(item.originalFontSize * minRatio) & "px"
        if item.originalWidth > 0.0:
          element.style.width = $(item.originalWidth * minRatio) & "px"
        if item.originalHeight > 0.0:
          element.style.height = $(item.originalHeight * minRatio) & "px"

      window.scrollTo(0, 0)

  proc newRenderer2D*(id: string, width = -1, height = -1,
                      hidpi = false): Renderer2D =
    ## Creates a new 2D renderer on a canvas element with the specified
    ## ID. When the ``width`` and ``height`` parameters are set to
    ## ``-1`` the whole screen will be used.
    ##
    ## This proc assumes that the document has been loaded.
    ##
    ## The ``hidpi`` parameter determines whether to create a High
    ## DPI canvas.

    var canvas = document.getElementById(id).EmbedElement
    var context = canvas.getContext("2d")
    if hidpi:
      let ratio = getPixelRatio()
      canvas.width = int(getWidth(width).float * ratio)
      canvas.height = int(getHeight(height).float * ratio)
      canvas.style.width = $getWidth(width) & "px"
      canvas.style.height = $getHeight(height) & "px"
      context.setTransform(ratio, 0, 0, ratio, 0, 0)

    result = Renderer2D(
      canvas: canvas,
      context: context,
      preferredWidth: width,
      preferredHeight: height,
      scaleToScreen: false,
      positionedElements: @[],
      images: initTable[string, Image]()
    )

    var capturedResult = result
    window.addEventListener("resize",
      (ev: Event) => (resizeCanvas(capturedResult)))

    resizeCanvas(result)

  proc newSurface2D*(renderer: Renderer2D, width: int, height: int): Surface2D =
    result = Surface2D(
      canvas: document.createElement("canvas").EmbedElement
    )
    result.canvas.width = width
    result.canvas.height = height
    result.context = result.canvas.getContext("2d")

  proc destroy*(surface: Surface2D) =
    discard # No-op for JS.

  proc strokeLine*(renderer: Drawable2D, start, finish: Point, width = 1,
      style = "#000000", shadowBlur = 0, shadowColor = "#000000") =
    renderer.context.beginPath()
    renderer.context.moveTo(start.x, start.y)
    renderer.context.lineTo(finish.x, finish.y)
    renderer.context.lineWidth = width
    renderer.context.strokeStyle = style
    renderer.context.shadowBlur = shadowBlur
    renderer.context.shadowColor = shadowColor
    renderer.context.closePath()
    renderer.context.stroke()

    renderer.context.shadowBlur = 0

  proc strokeLines*(renderer: Drawable2D, points: seq[Point], width = 1,
      style = "#000000", shadowBlur = 0, shadowColor = "#000000") =
    if points.len == 0: return
    renderer.context.beginPath()

    renderer.context.moveTo(points[0].x, points[0].y)

    for i in 1 .. <points.len:
      renderer.context.lineTo(points[i].x, points[i].y)

    renderer.context.lineWidth = width
    renderer.context.strokeStyle = style
    renderer.context.shadowBlur = shadowBlur
    renderer.context.shadowColor = shadowColor
    renderer.context.closePath()
    renderer.context.stroke()

    renderer.context.shadowBlur = 0

  proc clear*(
    renderer: Drawable2D, style = "#000000"
  ) =
    renderer.context.beginPath()
    renderer.context.fillStyle = style
    renderer.context.clearRect(0, 0, renderer.canvas.width, renderer.canvas.height)

  proc fillRect*[T: SomeNumber, Y: SomeNumber](
    renderer: Drawable2D, x, y: T, width, height: Y, style = "#000000"
  ) =
    renderer.context.fillStyle = style
    renderer.context.fillRect(x, y, width, height)

  proc strokeRect*[T: SomeNumber, Y: SomeNumber](
    renderer: Drawable2D, x, y: T, width, height: Y, style = "#000000", lineWidth = 1
  ) =
    renderer.context.strokeStyle = style
    renderer.context.lineWidth = lineWidth
    renderer.context.strokeRect(x, y, width, height)

  proc fillText*(renderer: Drawable2D, text: string, pos: Point,
      style = "#000000", font = "12px Helvetica", center = false) =
    renderer.context.fillStyle = style
    renderer.context.font = font
    if center:
      renderer.context.textAlign = "center"
    renderer.context.fillText(text, pos.x, pos.y)
    renderer.context.textAlign = "left"

  proc getTextMetrics*(
    renderer: Drawable2D, text: string, font = "12px Helvetica"
  ): TextMetrics =
    renderer.context.font = font

    {.emit: """
      `result`.`width` = `renderer`.`context`.measureText(`text`).width;
    """.}

  proc setTranslation*(renderer: Drawable2D, pos: Point, zoom=1.0) =
    renderer.context.setTransform(zoom, 0, 0, zoom, pos.x, pos.y)

  proc centerOn*(renderer: Drawable2D, pos: Point, zoom=1.0) =
    renderer.context.translate(-pos.x, -pos.y)
    renderer.context.scale(zoom, zoom)
    renderer.context.translate(
      renderer.canvas.width / 2,
      renderer.canvas.height / 2
    )

  proc getWidth*(renderer: Drawable2D): int =
    renderer.canvas.width

  proc getHeight*(renderer: Drawable2D): int =
    renderer.canvas.height

  proc setProperties(renderer: Renderer2D, element: Element, pos: Point,
                     width, height, fontSize: float) =
    element.style.position = "absolute"
    element.style.margin = "0"
    element.style.marginLeft = $pos.x & "px"
    element.style.marginTop = $pos.y & "px"
    element.style.fontSize = $fontSize & "px"
    if width >= 0.0:
      element.style.width = $width & "px"

    if height >= 0.0:
      element.style.height = $height & "px"

    element.classList.add(positionedElementCssClass)
    renderer.positionedElements.add(PositionedElement(
      originalLeft: pos.x,
      originalTop: pos.y,
      element: element,
      originalFontSize: fontSize,
      originalWidth: width,
      originalHeight: height
    ))
    resizeCanvas(renderer)

  proc createTextElement*(renderer: Renderer2D, text: string, pos: Point,
                          style="#000000", fontSize=12.0,
                          fontFamily="Helvetica", width = -1.0): Element =
    ## This procedure allows you to draw crisp text on your canvas.
    ##
    ## Note that this creates a new DOM element which you should keep. If you
    ## need the text to move or its contents modified then use the `style`
    ## and `innerHTML` setters.
    ##
    ## **Warning:** Movement will fail if the canvas is scaled via the
    ## ``scaleToScreen`` option.
    let p = document.createElement("p")
    p.innerHTML = text
    renderer.setProperties(p, pos, width, 0.0, fontSize)

    p.style.fontFamily = fontFamily
    p.style.color = style

    renderer.canvas.parentNode.insertBefore(p, renderer.canvas)
    return p

  proc createTextBox*(renderer: Renderer2D, pos: Point, width = -1.0,
                      height = -1.0, fontSize = 12.0): Element =
    let input = document.createElement("input")
    input.EmbedElement.`type` = "text"
    renderer.setProperties(input, pos, width, height, fontSize)

    renderer.canvas.parentNode.insertBefore(input, renderer.canvas)
    return input.OptionElement

  proc createButton*(renderer: Renderer2D, pos: Point, text: string,
                     width = -1.0, height = -1.0, fontSize = 12.0,
                     fontFamily = "Helvetica"): Element =
    let input = document.createElement("input")
    input.EmbedElement.`type` = "button"
    input.OptionElement.value = text
    renderer.setProperties(input, pos, width, height, fontSize)
    input.style.fontFamily = fontFamily

    renderer.canvas.parentNode.insertBefore(input, renderer.canvas)
    return input.OptionElement

  proc `[]=`*(renderer: Drawable2D, pos: (int, int) | (float, float),
              color: Color) =
    let image = renderer.context.createImageData(1, 1)
    let (r, g, b) = color.extractRGB()
    image.data[0] = r
    image.data[1] = g
    image.data[2] = b
    image.data[3] = 255

    renderer.context.putImageData(image, round(pos[0]), round(pos[1]))

  proc `[]=`*(renderer: Drawable2D, pos: Point, color: Color) =
    renderer[(pos.x, pos.y)] = color

  proc setRotation*(renderer: Drawable2D, rotation: float) =
    ## Sets the current renderer surface rotation to the specified radians value.
    renderer.context.rotate((PI - renderer.rotation) + rotation)
    renderer.rotation = rotation

  proc setScaleToScreen*(renderer: Renderer2D, value: bool) =
    ## When set to ``true`` this property will scale the renderer's canvas to
    ## fit the device's screen. Elements created using the procedures defined
    ## in this module will also be handled, every object will be resized by
    ## either the ratio of screen width to canvas width or screen height to
    ## canvas height, whichever one is smallest.
    renderer.scaleToScreen = value

    renderer.resizeCanvas()

  proc getScaleToScreen*(renderer: Renderer2D): bool =
    renderer.scaleToScreen

  proc drawImage*(
    renderer: Drawable2D, url: string, pos: Point, width, height: int,
    align: ImageAlignment = ImageAlignment.Center, degrees: float = 0
  ) =
    assert width != 0 and height != 0
    let pos = adjustPos(width, height, pos, align)
    renderer.context.save()
    renderer.context.translate(pos.x.int + width div 2, int(pos.y) + height div 2)
    renderer.context.rotate(degToRad(degrees))
    renderer.context.translate(int(-pos.x) - width div 2, int(-pos.y) - height div 2)
    if url in renderer.images:
      let img = renderer.images[url]
      if img.complete:
        renderer.context.drawImage(img, pos.x, pos.y, width, height)
    else:
      let img = newImage()
      img.src = url
      img.onload =
        proc () =
          renderer.context.drawImage(img, pos.x, pos.y, width, height)
      renderer.images[url] = img

    renderer.context.restore()

  proc drawImageFromMemory*(
    renderer: Drawable2D, contents: string, pos: Point, width, height: int,
    align: ImageAlignment = ImageAlignment.Center, degrees: float = 0
  ) =
    # TODO: Other image formats. Assuming SVG here
    let header = "data:image/svg+xml;base64,"

    drawImage(renderer, header & base64.encode(contents), pos, width, height, align, degrees)

  proc copy*[T: Drawable2D, Y: Surface2D](renderer: T, other: Y, pos: Point, width, height: int) =
    renderer.context.drawImage(other.canvas, pos.x, pos.y, width, height)

  proc fillCircle*(
    renderer: Drawable2D, pos: Point, radius: int | float, style = "#000000"
  ) =
    renderer.context.beginPath()
    renderer.context.arc(pos.x, pos.y, radius, 0, 2 * math.PI)
    renderer.context.fillStyle = style
    renderer.context.closePath()
    renderer.context.fill()

  proc onFrame(renderer: Renderer2D, frameTime: float, onTick: proc (elapsedTime: float)) =
    let r = window.requestAnimationFrame((time: float) => onFrame(renderer, time, onTick))
    let elapsedTime = frameTime - renderer.lastFrameUpdate
    renderer.lastFrameUpdate = frameTime
    onTick(elapsedTime)

  proc startLoop*(renderer: Renderer2D, onTick: proc (elapsedTime: float)) =
    onFrame(renderer, 0, onTick)

  proc preventDefault*(ev: TouchEvent | MouseEvent | KeyboardEvent) =
    dom.preventDefault(ev)

  proc `onKeyDown=`*(renderer: Renderer2D, onKeyDown: proc (event: KeyboardEvent)) =
    window.addEventListener("keydown", (ev: Event) => onKeyDown(ev.KeyboardEvent))

  proc `onMouseButtonDown=`*(renderer: Renderer2D, onMouseButtonDown: proc (event: MouseButtonEvent)) =
    window.addEventListener("mousedown", (ev: Event) => onMouseButtonDown(ev.MouseButtonEvent))

  proc `onMouseButtonUp=`*(renderer: Renderer2D, onMouseButtonUp: proc (event: MouseButtonEvent)) =
    window.addEventListener("mouseup", (ev: Event) => onMouseButtonUp(ev.MouseButtonEvent))

  proc `onMouseMotion=`*(renderer: Renderer2D, onMouseMotion: proc (event: MouseMotionEvent)) =
    window.addEventListener("mousemove", (ev: Event) => onMouseMotion(ev.MouseMotionEvent))

  proc `onTouchMove=`*(renderer: Renderer2D, onTouchMotion: proc (event: TouchEvent)) =
    window.addEventListener("touchmove", (ev: Event) => onTouchMotion(ev.TouchEvent))

  proc `onTouchStart=`*(renderer: Renderer2D, onTouchStart: proc (event: TouchEvent)) =
    window.addEventListener("touchstart", (ev: Event) => onTouchStart(ev.TouchEvent))

  proc `onTouchEnd=`*(renderer: Renderer2D, onTouchEnd: proc (event: TouchEvent)) =
    window.addEventListener("touchend", (ev: Event) => onTouchEnd(ev.TouchEvent))

  proc `onResize=`*(renderer: Renderer2D, onResize: proc (width, height: int)) =
    window.addEventListener("resize",
      (ev: Event) => onResize(renderer.canvas.width, renderer.canvas.height)
    )

  proc moveTo*(renderer: Drawable2D, x, y: float | int) =
    renderer.context.moveTo(x, y)

  proc lineTo*(renderer: Drawable2D, x, y: float | int) =
    renderer.context.lineTo(x, y)

  proc beginPath*(renderer: Drawable2D) =
    renderer.context.beginPath()

  proc closePath*(renderer: Drawable2D) =
    renderer.context.closePath()

  proc fillPath*(renderer: Drawable2D, style: string) =
    renderer.context.fillStyle = style
    renderer.context.fill()

  proc strokePath*(renderer: Drawable2D, style: string, lineWidth: int) =
    renderer.context.strokeStyle = style
    renderer.context.lineWidth = lineWidth
    renderer.context.stroke()

  proc scale*(renderer: Drawable2D, x, y: float) =
    renderer.context.scale(x, y)

  proc translate*(renderer: Drawable2D, x, y: float) =
    renderer.context.translate(x, y)

  proc save*(renderer: Drawable2D) =
    renderer.context.save()

  proc restore*(renderer: Drawable2D) =
    renderer.context.restore()

  proc clipRect*(renderer: Drawable2D, pos: Point[int], width, height: int) =
    {.emit: """
      var region = new Path2D();
      region.rect(`pos`.`x`, `pos`.`y`, `width`, `height`);
      `renderer`.`context`.clip(region, "nonzero");
    """.}
else:
  # SDL2
  import sdl2_utils
  export KeyboardEventObj, MouseButtonEventObj, MouseMotionEventObj

  checkError sdl2.init(INIT_EVERYTHING)
  checkError ttfInit()
  proc newRenderer2D*(id: string, width = 640, height = 480,
                      hidpi = false): Renderer2D =

    var window: WindowPtr
    var renderer: RendererPtr
    var flags =
      SDL_WINDOW_SHOWN or SDL_WINDOW_RESIZABLE
    if width == -1 and height == -1:
      flags = flags or SDL_WINDOW_FULLSCREEN
    checkError createWindowAndRenderer(
      width.cint, height.cint, flags, window, renderer
    )

    result = Renderer2D(
      window: window,
      sdlRenderer: renderer,
      preferredWidth: width,
      preferredHeight: height,
      scaleToScreen: false,
      lastFrameUpdate: 0,
      scalingFactor: Point[float](x: 1.0, y: 1.0)
    )

    for ev in EventKind:
      result.events[ev] = nil

    discard sdl2.setHint(HINT_RENDER_SCALE_QUALITY, "linear") # TODO: report this?

    # var capturedResult = result
    # window.addEventListener("resize",
    #   (ev: Event) => (resizeCanvas(capturedResult)))

    # resizeCanvas(result)=

  proc newSurface2D*(renderer: Renderer2D, width: int, height: int): Surface2D =
    result = Surface2D(
      renderer2D: renderer,
      texture: sdl2.createTexture(
        renderer.sdlRenderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET,
        width.cint, height.cint
      ),
      preferredWidth: width,
      preferredHeight: height
    )
    checkError result.texture

  proc destroy*(surface: Surface2D) =
    destroy(surface.texture)

  proc getRenderer(renderer: Renderer2D): Renderer2D = renderer
  proc getRenderer(surface: Surface2D): Renderer2D = surface.renderer2D

  proc getSdlRenderer(renderer: Renderer2D): RendererPtr =
    checkError renderer.sdlRenderer.setRenderTarget(nil)
    return renderer.sdlRenderer

  proc getSdlRenderer(surface: Surface2D): RendererPtr =
    checkError surface.renderer2D.sdlRenderer.setRenderTarget(surface.texture)
    return surface.renderer2D.sdlRenderer

  proc getSdlTexture(surface: Renderer2D): TexturePtr =
    result = surface.sdlRenderer.getRenderTarget()
    checkError result

  proc getSdlTexture(surface: Surface2D): TexturePtr =
    return surface.texture

  proc startLoop*(renderer: Renderer2D, onTick: proc (elapsedTime: float)) =
    var
      event = sdl2.defaultEvent
    #   fpsman: FpsManager
    # fpsman.init()
    # fpsman.setFramerate(60)
    renderer.lastFrameUpdate = getPerformanceCounter()

    block eventLoop:
      while true:
        while pollEvent(event):
          case event.kind
          of QuitEvent:
            break eventLoop
          of EventType.KeyDown:
            if not renderer.events[EventKind.KeyDown].isNil:
              renderer.events[EventKind.KeyDown](event)
          of EventType.MouseButtonDown:
            if not renderer.events[EventKind.MouseButtonDown].isNil:
              renderer.events[EventKind.MouseButtonDown](event)
          of EventType.MouseButtonUp:
            if not renderer.events[EventKind.MouseButtonUp].isNil:
              renderer.events[EventKind.MouseButtonUp](event)
          of EventType.MouseMotion:
            if not renderer.events[EventKind.MouseMotion].isNil:
              renderer.events[EventKind.MouseMotion](event)
          of EventType.FingerMotion:
            if not renderer.events[EventKind.FingerMotion].isNil:
              renderer.events[EventKind.FingerMotion](event)
          of EventType.FingerUp:
            if not renderer.events[EventKind.FingerUp].isNil:
              renderer.events[EventKind.FingerUp](event)
          of EventType.FingerDown:
            if not renderer.events[EventKind.FingerDown].isNil:
              renderer.events[EventKind.FingerDown](event)
          of EventType.WindowEvent:
            if cast[WindowEventObj](event).event == WindowEvent_SizeChanged:
              if not renderer.events[EventKind.SizeChanged].isNil:
                renderer.events[EventKind.SizeChanged](event)
          else: discard

        let frameTime = getPerformanceCounter()
        let elapsedTime = ((frameTime - renderer.lastFrameUpdate)*1000) / getPerformanceFrequency().float
        renderer.lastFrameUpdate = frameTime

        checkError renderer.getSdlRenderer.setDrawColor(0,0,0,255)
        checkError renderer.getSdlRenderer.clear()

        onTick(elapsedTime.float)

        renderer.getSdlRenderer.present()
        # fpsman.delay

    destroy renderer.getSdlRenderer
    destroy renderer.window

  type
    KeyboardEvent* = KeyboardEventObj
    MouseButtonEvent* = MouseButtonEventObj
    MouseMotionEvent* = MouseMotionEventObj
    TouchEvent* = object
      ev: TouchFingerEventObj
      winWidth, winHeight: int # Needed to denormalize the `x` and `y`.

  proc keyCode*(event: KeyboardEvent): int =
    event.keysym.sym.int

  proc key*(event: KeyboardEvent): string =
    $getScancodeName(event.keysym.scancode)

  proc preventDefault*(event: KeyboardEvent | MouseButtonEvent | MouseMotionEvent | TouchEvent) = discard

  proc clientX*(event: MouseButtonEvent | MouseMotionEvent): int =
    event.x.int

  proc clientY*(event: MouseButtonEvent | MouseMotionEvent): int =
    event.y.int

  type
    Touch* = object
      identifier*: FingerID
      clientX*, clientY*: float
      force*: float

  proc touches*(event: TouchEvent): seq[Touch] =
    let count = getNumTouchFingers(event.ev.touchID)
    for i in 0 ..< count:
      let finger = getTouchFinger(event.ev.touchID, i)
      checkError finger
      result.add(Touch(
        identifier: finger.id,
        clientX: finger.x * event.winWidth.cfloat,
        clientY: finger.y * event.winHeight.cfloat,
        force: finger.pressure
      ))
    if count == 0:
      result.add(Touch(
        identifier: event.ev.touchId,
        clientX: event.ev.x * event.winWidth.cfloat,
        clientY: event.ev.y * event.winHeight.cfloat,
        force: event.ev.pressure
      ))

  proc `onKeyDown=`*(renderer: Renderer2D, onKeyDown: proc (event: KeyboardEventObj)) =
    renderer.events[EventKind.KeyDown] =
      proc (event: sdl2.Event) =
        let ev = cast[sdl2.KeyboardEventObj](event)
        if not onKeyDown.isNil:
          onKeyDown(ev)

  proc `onMouseButtonDown=`*(renderer: Renderer2D, onMouseButtonDown: proc (event: MouseButtonEventObj)) =
    renderer.events[EventKind.MouseButtonDown] =
      proc (event: sdl2.Event) =
        let ev = cast[sdl2.MouseButtonEventObj](event)
        if not onMouseButtonDown.isNil:
          onMouseButtonDown(ev)

  proc `onMouseButtonUp=`*(renderer: Renderer2D, onMouseButtonUp: proc (event: MouseButtonEventObj)) =
    renderer.events[EventKind.MouseButtonUp] =
      proc (event: sdl2.Event) =
        let ev = cast[sdl2.MouseButtonEventObj](event)
        if not onMouseButtonUp.isNil:
          onMouseButtonUp(ev)

  proc `onMouseMotion=`*(renderer: Renderer2D, onMouseMotion: proc (event: MouseMotionEventObj)) =
    renderer.events[EventKind.MouseMotion] =
      proc (event: sdl2.Event) =
        let ev = cast[sdl2.MouseMotionEventObj](event)
        if not onMouseMotion.isNil:
          onMouseMotion(ev)

  proc toTouchEvent(renderer: Renderer2D, ev: TouchFingerEventObj): TouchEvent =
    let size = getSize(renderer.getSdlRenderer())
    TouchEvent(
      ev: ev,
      winWidth: size.width,
      winHeight: size.height
    )

  proc `onTouchMove=`*(renderer: Renderer2D, onTouchMove: proc (event: TouchEvent)) =
    renderer.events[EventKind.FingerMotion] =
      proc (event: sdl2.Event) =
        let ev = cast[sdl2.TouchFingerEventObj](event)
        if not onTouchMove.isNil:
          onTouchMove(toTouchEvent(renderer, ev))

  proc `onTouchStart=`*(renderer: Renderer2D, onTouchStart: proc (event: TouchEvent)) =
    renderer.events[EventKind.FingerDown] =
      proc (event: sdl2.Event) =
        let ev = cast[sdl2.TouchFingerEventObj](event)
        if not onTouchStart.isNil:
          onTouchStart(toTouchEvent(renderer, ev))

  proc `onTouchEnd=`*(renderer: Renderer2D, onTouchEnd: proc (event: TouchEvent)) =
    renderer.events[EventKind.FingerUp] =
      proc (event: sdl2.Event) =
        let ev = cast[sdl2.TouchFingerEventObj](event)
        if not onTouchEnd.isNil:
          onTouchEnd(toTouchEvent(renderer, ev))

  proc getWidth*(renderer: Drawable2D): int
  proc getHeight*(renderer: Drawable2D): int
  proc `onResize=`*(renderer: Renderer2D, onResize: proc (width, height: int)) =
    renderer.events[EventKind.SizeChanged] =
      proc (event: sdl2.Event) =
        if not onResize.isNil:
          onResize(renderer.getWidth, renderer.getHeight)

  # Drawing utils

  proc applyTranslation[T: SomeNumber](renderer: Drawable2D, x, y: T): (cint, cint) =
    return (
      cint(x + renderer.translationFactor.x.T),
      cint(y + renderer.translationFactor.y.T)
    )

  proc applyTranslation[T: SomeNumber](renderer: Drawable2D, pos: Point[T]): Point[T] =
    return Point[T](
      x: pos.x + renderer.translationFactor.x.T,
      y: pos.y + renderer.translationFactor.y.T
    )

  # Drawing

  proc setColor(renderer: Drawable2D, style: string) =
    let color = parseHtmlColor(style).rgba()

    checkError renderer.getSdlRenderer.setDrawColor(
      color.r.uint8, color.g.uint8, color.b.uint8, color.a.uint8
    )
    checkError setDrawBlendMode(renderer.getSdlRenderer, BlendMode_BLEND)

  proc clear*(
    renderer: Drawable2D, style = "#000000"
  ) =
    setColor(renderer, style)
    checkError renderer.getSdlTexture().setTextureBlendMode(BlendMode_BLEND)
    checkError renderer.getSdlRenderer.clear()

  proc fillRect*[T: SomeNumber, Y: SomeNumber](
    renderer: Drawable2D, x, y: T, width, height: Y, style = "#000000"
  ) =
    setColor(renderer, style)
    let (x, y) = applyTranslation(renderer, x, y)
    var rect = (x, y, width.cint, height.cint)
    checkError renderer.getSdlRenderer.fillRect(addr rect)

  proc strokeRect*[T: SomeNumber, Y: SomeNumber](
    renderer: Drawable2D, x, y: T, width, height: Y, style = "#000000", lineWidth = 1
  ) =
    setColor(renderer, style)
    let (x, y) = applyTranslation(renderer, x, y)
    var rect = (x.cint, y.cint, width.cint, height.cint)
    # TODO: Line width
    checkError renderer.getSdlRenderer.drawRect(addr rect)

  proc fillCircle*(
    renderer: Drawable2D, pos: Point, radius: int | float, style = "#000000"
  ) =
    # TODO: Remove sdl2_gfx circle drawing because it's a crappy dependency.
    renderer.fillRect(pos.x, pos.y, radius, radius, style)

  proc drawImage(
    renderer: Drawable2D, img: TexturePtr, pos: Point, width, height: int,
    align: ImageAlignment = ImageAlignment.Center, degrees: float = 0
  ) =
    # TODO: Don't load textures on each draw (!) plus implement SVG workaround:
    #  * control rastered scale by changing width/height param of SVG
    #  * https://bugzilla.libsdl.org/show_bug.cgi?id=4072
    assert width != 0 and height != 0
    checkError img

    let pos = applyTranslation(renderer, adjustPos(width, height, pos, align))
    var center =
      case align
      of ImageAlignment.Center:
        (cint(width div 2), cint(height div 2))
      of ImageAlignment.TopLeft:
        (0.cint, 0.cint)

    var destRect = sdl2.rect(pos.x.cint, pos.y.cint, width.cint, height.cint)
    checkError renderer.getSdlRenderer.copyEx(img, nil, addr destRect, degrees, addr center)

  proc drawImage*(
    drawable: Drawable2D, file: string, pos: Point, width, height: int,
    align: ImageAlignment = ImageAlignment.Center, degrees: float = 0
  ) =
    let file =
      if file.isAbsolute(): file
      else: getCurrentDir() / file
    if file notin drawable.getRenderer().texturesFromFile:
      drawable.getRenderer().texturesFromFile[file] =
        loadTexture(drawable.getSdlRenderer, file)
      checkError drawable.getRenderer().texturesFromFile[file]
      # TODO: We should limit the number of items in our cache.

    let img = drawable.getRenderer().texturesFromFile[file]
    drawImage(drawable, img, pos, width, height, align, degrees)

  proc drawImageFromMemory*(
    drawable: Drawable2D, contents: string, pos: Point, width, height: int,
    align: ImageAlignment = ImageAlignment.Center, degrees: float = 0
  ) =
    if contents notin drawable.getRenderer().texturesFromString:
      let rw = rwFromMem(unsafeAddr contents[0], contents.len.cint)
      defer: freeRW(rw)
      drawable.getRenderer().texturesFromString[contents] =
        loadTexture_RW(drawable.getSdlRenderer, rw, 0)
      checkError drawable.getRenderer().texturesFromString[contents]
      # TODO: We should limit the number of items in our cache.
    let img = drawable.getRenderer().texturesFromString[contents]
    drawImage(drawable, img, pos, width, height, align, degrees)

  proc copy*[T: Drawable2D, Y: Surface2D](renderer: T, other: Y, pos: Point, width, height: int) =
    let pos = applyTranslation(renderer, pos)

    var destRect = sdl2.rect(pos.x.cint, pos.y.cint, width.cint, height.cint)
    checkError renderer.getSdlRenderer.copyEx(other.texture, nil, addr destRect, 0, nil)

  proc loadFont(renderer: Renderer2D, font: string): FontPtr =
    let s = font.split(" ")
    var fontStyle: cint = TTF_STYLE_NORMAL
    var index = 0
    while index < s.len:
      if s[index].endsWith("px"): break
      case s[index].toLower()
      of "bold":
        fontStyle = fontStyle or TTF_STYLE_BOLD
      of "italic":
        fontStyle = fontStyle or TTF_STYLE_ITALIC
      else:
        assert false
      index.inc()

    assert s[index].endsWith("px")

    let size = parseInt(s[index][0 .. ^3]).cint
    index.inc()
    let name = s[index].replace(" ", "_") & ".ttf"

    let key = (name, size)
    if key notin renderer.fontCache:
      let fontPath =
        when defined(ios):
          $getResourcePathIOS(name.changeFileExt(""), "ttf")
        else:
          getCurrentDir() / "fonts" / name
      renderer.fontCache[key] = openFont(fontPath, size)

    result = renderer.fontCache[key]
    checkError(result)
    setFontStyle(result, fontStyle)

  proc fillText*(renderer: Drawable2D, text: string, pos: Point,
      style = "#000000", font = "12px Helvetica", center = false) =
    let color = parseHtmlColor(style).rgba()
    let font =
      when renderer is Renderer2D:
        renderer.loadFont(font)
      else:
        renderer.renderer2D.loadFont(font)
    let sdlColor = sdl2.color(color.r, color.g, color.b, color.a)
    checkError setDrawBlendMode(renderer.getSdlRenderer, BlendMode_BLEND)

    let textSurface = renderUtf8Blended(font, text, sdlColor)
    checkError textSurface
    defer: freeSurface(textSurface)

    let texture = createTextureFromSurface(renderer.getSdlRenderer, textSurface)
    checkError texture
    defer: destroy(texture)
    let width = textSurface.w
    let height = textSurface.h

    let pos = applyTranslation(renderer, pos)
    var destRect = sdl2.rect(
      pos.x.cint - (if center: width div 2 else: 0),
      pos.y.cint - (if center: height div 2 else: 0),
      width, height
    )
    # echo("Render: ", destRect, " ", text)
    checkError sdl2.copy(renderer.getSdlRenderer, texture, nil, addr destRect)

  proc getTextMetrics*(
    renderer: Drawable2D, text: string, font = "12px Helvetica"
  ): TextMetrics =
    let font =
      when renderer is Renderer2D:
        renderer.loadFont(font)
      else:
        renderer.renderer2D.loadFont(font)

    checkError sizeUtf8(font, text, addr result.width, addr result.height)

  # Path drawing
  proc lineTo*(renderer: Drawable2D, x, y: float | int) =
    renderer.currentPath.add(Point[int](x: x.int, y: y.int))

  proc moveTo*(renderer: Drawable2D, x, y: float | int) =
    assert renderer.currentPath.len == 0
    renderer.lineTo(x, y)

  proc beginPath*(renderer: Drawable2D) =
    renderer.currentPath = @[]

  proc closePath*(renderer: Drawable2D) =
    discard

  proc fillPath*(renderer: Drawable2D, style: string) =
    discard # TODO;

  proc strokePath*(renderer: Drawable2D, style: string, lineWidth: int) =
    # TODO: This algorithm doesn't have the same semantics as HTML canvas
    let color = parseHtmlColor(style)
    for i in 0 ..< renderer.currentPath.len:
      if i == renderer.currentPath.len-1: break
      let next = i+1
      let first = applyTranslation(renderer, renderer.currentPath[i])
      let second = applyTranslation(renderer, renderer.currentPath[next])
      checkError setDrawBlendMode(renderer.getSdlRenderer, BlendMode_BLEND)
      if first.x == second.x or first.y == second.y:
        var first = first
        var second = second
        let isVertical = first.x == second.x
        if not isVertical and second.x < first.x:
          swap(first, second)
        elif isVertical and second.y < first.y:
          swap(first, second)

        let width =
          if not isVertical:
            sqrt(distanceSquared(first, second).float)
          else:
            lineWidth.float
        let height =
          if isVertical:
            sqrt(distanceSquared(first, second).float)
          else:
            lineWidth.float

        var rect = (
          x: cint(first.x - (if isVertical: lineWidth div 2 else: 0)),
          y: cint(first.y - (if not isVertical: lineWidth div 2 else: 0)),
          w: width.cint,
          h: height.cint,
        )
        checkError setDrawColor(renderer.getSdlRenderer(), color.rgba().r, color.rgba().g, color.rgba().b, 255'u8)
        checkError renderer.getSdlRenderer().fillRect(
          rect
        )
      else:
        drawThickLine(
          renderer.getSdlRenderer,
          first.x,
          first.y,
          second.x - (if i == 0 and first.y == second.y: 1 else: 0),
          second.y - (if i == 0 and first.x == second.x: 1 else: 0),
          lineWidth,
          color
        )


  proc clipRect*(renderer: Drawable2D, pos: Point[int], width, height: int) =
    let pos = applyTranslation(renderer, pos)
    var rect = sdl2.rect(pos.x.cint, pos.y.cint, width.cint, height.cint)
    checkError sdl2.setClipRect(renderer.getSdlRenderer, addr rect)

  # Viewport functions
  proc scale*(renderer: Drawable2D, x, y: float) =
    renderer.scalingFactor = vec.Point[float](x: x, y: y)
    renderer.getSdlRenderer.setScale(x, y)

  proc translate*(renderer: Drawable2D, x, y: float) =
    renderer.translationFactor = vec.Point[int](x: x.int, y: y.int)

  proc save*(renderer: Drawable2D) =
    checkError sdl2.setClipRect(renderer.getSdlRenderer, nil)
    renderer.savedFactors.add((renderer.scalingFactor, renderer.translationFactor))

  proc restore*(renderer: Drawable2D) =
    checkError sdl2.setClipRect(renderer.getSdlRenderer, nil)
    let (scalingFactor, translationFactor) =
      if renderer.savedFactors.len > 0: renderer.savedFactors.pop()
      else: (Point[float](x: 1, y: 1), Point[int](x: 0, y: 0))
    renderer.scalingFactor = scalingFactor
    renderer.getSdlRenderer.setScale(renderer.scalingFactor.x, renderer.scalingFactor.y)
    renderer.translationFactor = translationFactor

  # Accessors
  proc getWidth*(renderer: Drawable2D): int =
    var res: cint
    checkError getRendererOutputSize(renderer.getSdlRenderer, addr res, nil)
    return res

  proc getHeight*(renderer: Drawable2D): int =
    var res: cint
    checkError getRendererOutputSize(renderer.getSdlRenderer, nil, addr res)
    return res

when defined(js):
  proc setWindowTitle*(window: Renderer2D, title: string) =
    let ctitle = cstring(title)
    {.emit: """
      document.title = `ctitle`;
    """.}
else:
  proc setWindowTitle*(renderer: Renderer2D, title: string) =
    renderer.window.setTitle(title)