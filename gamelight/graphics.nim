import sugar, colors, math, tables
import dom, jsconsole
import canvasjs, vec

type
  Renderer2D* = ref object
    canvas: EmbedElement
    context: CanvasRenderingContext
    preferredWidth: int
    preferredHeight: int
    rotation: float
    scaleToScreen: bool
    positionedElements: seq[PositionedElement]
    images: Table[string, Image]

  PositionedElement = ref object
    originalLeft, originalTop: float
    originalFontSize: float
    originalWidth, originalHeight: float
    element: Element

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

proc strokeLine*(renderer: Renderer2D, start, finish: Point, width = 1,
    style = "#000000", shadowBlur = 0, shadowColor = "#000000") =
  renderer.context.beginPath()
  renderer.context.moveTo(start.x, start.y)
  renderer.context.lineTo(finish.x, finish.y)
  renderer.context.lineWidth = width
  renderer.context.strokeStyle = style
  renderer.context.shadowBlur = shadowBlur
  renderer.context.shadowColor = shadowColor
  renderer.context.stroke()

  renderer.context.shadowBlur = 0

proc strokeLines*(renderer: Renderer2D, points: seq[Point], width = 1,
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
  renderer.context.stroke()

  renderer.context.shadowBlur = 0

proc fillRect*(renderer: Renderer2D, x, y, width, height: int | float,
    style = "#000000") =
  renderer.context.fillStyle = style
  renderer.context.fillRect(x, y, width, height)

proc strokeRect*(renderer: Renderer2D, x, y, width, height: int | float,
    style = "#000000", lineWidth = 1) =
  renderer.context.strokeStyle = style
  renderer.context.lineWidth = lineWidth
  renderer.context.strokeRect(x, y, width, height)

proc fillText*(renderer: Renderer2D, text: string, pos: Point,
    style = "#000000", font = "12px Helvetica") =
  renderer.context.fillStyle = style
  renderer.context.font = font
  renderer.context.fillText(text, pos.x, pos.y)

proc setTranslation*(renderer: Renderer2D, pos: Point) =
  renderer.context.setTransform(1, 0, 0, 1, pos.x, pos.y)

proc getWidth*(renderer: Renderer2D): int =
  renderer.canvas.width

proc getHeight*(renderer: Renderer2D): int =
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

proc `[]=`*(renderer: Renderer2D, pos: (int, int) | (float, float),
            color: Color) =
  let image = renderer.context.createImageData(1, 1)
  let (r, g, b) = color.extractRGB()
  image.data[0] = r
  image.data[1] = g
  image.data[2] = b
  image.data[3] = 255

  renderer.context.putImageData(image, round(pos[0]), round(pos[1]))

proc `[]=`*(renderer: Renderer2D, pos: Point, color: Color) =
  renderer[(pos.x, pos.y)] = color

proc setRotation*(renderer: Renderer2D, rotation: float) =
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

type
  ImageAlignment* = enum
    Center, TopLeft

proc adjustPos(width, height: int, pos: Point, align: ImageAlignment): Point =
  result = pos
  case align
  of Center:
    result = Point(
      x: result.x - (width / 2),
      y: result.y - (height / 2)
    )
  of TopLeft:
    discard

proc drawImage*(
  renderer: Renderer2D, url: string, pos: Point, width, height: int,
  align: ImageAlignment = ImageAlignment.Center, degrees: float = 0
) =
  assert width != 0 and height != 0
  let pos = adjustPos(width, height, pos, align)
  renderer.context.save()
  renderer.context.translate(pos.x + width / 2, pos.y + height / 2)
  renderer.context.rotate(degToRad(degrees))
  renderer.context.translate(-pos.x - width / 2, -pos.y - height / 2)
  if url in renderer.images:
    let img = renderer.images[url]
    renderer.context.drawImage(img, pos.x, pos.y, width, height)
  else:
    let img = newImage()
    img.src = url
    img.onload =
      proc () =
        renderer.context.drawImage(img, pos.x, pos.y, width, height)
    renderer.images[url] = img

  renderer.context.restore()

proc fillCircle*(
  renderer: Renderer2D, pos: Point, radius: int | float, style = "#000000"
) =
  renderer.context.beginPath()
  renderer.context.arc(pos.x, pos.y, radius, 0, 2 * math.PI)
  renderer.context.fillStyle = style
  renderer.context.fill()