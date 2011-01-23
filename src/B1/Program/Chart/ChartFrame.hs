module B1.Program.Chart.ChartFrame
  ( drawChartFrame
  ) where
  
import Control.Monad
import Data.Char
import Data.Maybe
import Graphics.Rendering.FTGL
import Graphics.Rendering.OpenGL
import Graphics.UI.GLFW

import B1.Data.Action
import B1.Data.Range
import B1.Graphics.Rendering.OpenGL.Shapes
import B1.Graphics.Rendering.OpenGL.Utils
import B1.Program.Chart.Animation
import B1.Program.Chart.Dirty
import B1.Program.Chart.Resources

type Symbol = String

data Content = Instructions | Chart Symbol

data Frame = Frame
  { content :: Content
  , scaleAnimation :: Animation (GLfloat, Dirty)
  , alphaAnimation :: Animation (GLfloat, Dirty)
  }

data FrameState = FrameState
  { currentSymbol :: String
  , nextSymbol :: String
  , currentFrame :: Maybe Frame
  , previousFrame :: Maybe Frame
  }

drawChartFrame :: Resources -> IO (Action Resources Dirty, Dirty)
drawChartFrame resources = drawChartFrameLoop initState resources
  where
    instructionsFrame = Frame
      { content = Instructions
      , scaleAnimation = incomingScaleAnimation
      , alphaAnimation = incomingAlphaAnimation
      }

    initState = FrameState
      { currentSymbol = ""
      , nextSymbol = ""
      , currentFrame = Just instructionsFrame 
      , previousFrame = Nothing
      }

incomingScaleAnimation :: Animation (GLfloat, Dirty)
incomingScaleAnimation = animateOnce $ linearRange 1 1 30

incomingAlphaAnimation :: Animation (GLfloat, Dirty)
incomingAlphaAnimation = animateOnce $ linearRange 0 1 30

outgoingScaleAnimation :: Animation (GLfloat, Dirty)
outgoingScaleAnimation = animateOnce $ linearRange 1 1.25 30

outgoingAlphaAnimation :: Animation (GLfloat, Dirty)
outgoingAlphaAnimation = animateOnce $ linearRange 1 0 30

drawChartFrameLoop :: FrameState -> Resources
    -> IO (Action Resources Dirty, Dirty)
drawChartFrameLoop state resources = do
  loadIdentity
  translateToCenter resources

  mapM_ (drawFrame resources nextState) allFrames
  drawNextSymbol resources nextState

  return (Action (drawChartFrameLoop nextState), nextDirty)

  where
    nextState = (refreshSymbolState resources
        . refreshCurrentFrame resources) state
    allFrames = catMaybes [currentFrame nextState, previousFrame nextState]
    nextDirty = any isDirtyFrame allFrames

isDirtyFrame :: Frame -> Bool
isDirtyFrame (Frame
    { scaleAnimation = scaleAnimation
    , alphaAnimation = alphaAnimation
    }) = any (snd . getCurrentFrame) [scaleAnimation, alphaAnimation]

translateToCenter :: Resources -> IO ()
translateToCenter resources =
  translate $ vector3 (sideBarWidth resources + (mainFrameWidth resources) / 2)
      (mainFrameHeight resources / 2) 0

mainFrameWidth :: Resources -> GLfloat
mainFrameWidth resources = windowWidth resources - sideBarWidth resources

mainFrameHeight :: Resources -> GLfloat
mainFrameHeight resources = windowHeight resources

drawFrame :: Resources -> FrameState -> Frame -> IO ()
drawFrame resources state (Frame
    { content = content
    , scaleAnimation = scaleAnimation
    , alphaAnimation = alphaAnimation
    }) = do
  let scaleAmount = fst . getCurrentFrame $ scaleAnimation
      alphaAmount = fst . getCurrentFrame $ alphaAnimation
  preservingMatrix $ do
    scale3 scaleAmount scaleAmount 1
    color $ blue alphaAmount
    drawFrameBorder resources

    color $ green alphaAmount
    case content of
      Chart _ -> drawCurrentSymbol resources content
      _ -> drawCenteredInstructions resources

blue :: GLfloat -> Color4 GLfloat
blue alpha = color4 0 0.25 1 alpha

green :: GLfloat -> Color4 GLfloat
green alpha = color4 0.25 1 0 alpha

black :: GLfloat -> Color4 GLfloat
black alpha = color4 0 0 0 alpha

refreshCurrentFrame :: Resources -> FrameState -> FrameState
refreshCurrentFrame resources
    state@FrameState
      { currentFrame = currentFrame
      , previousFrame = previousFrame
      } = state
  { currentFrame = nextFrame currentFrame
  , previousFrame = nextFrame previousFrame
  }

nextFrame :: Maybe Frame -> Maybe Frame
nextFrame Nothing = Nothing
nextFrame (Just frame) = Just $ frame
  { scaleAnimation = getNextAnimation $ scaleAnimation frame
  , alphaAnimation = getNextAnimation $ alphaAnimation frame
  }

refreshSymbolState :: Resources -> FrameState -> FrameState

-- Append to the next symbol if the key is just a character...
refreshSymbolState (Resources { keyPress = Just (CharKey char) })
    state@FrameState { nextSymbol = nextSymbol }
  | isAlpha char = state { nextSymbol = nextSymbol ++ [char] }
  | otherwise = state

-- BACKSPACE deletes one character in a symbol...
refreshSymbolState (Resources { keyPress = Just (SpecialKey BACKSPACE) })
    state@FrameState { nextSymbol = nextSymbol }
  | length nextSymbol < 1 = state
  | otherwise = state { nextSymbol = trimmedSymbol }
  where
    trimmedSymbol = take (length nextSymbol - 1) nextSymbol

-- ENTER makes the next symbol the current symbol.
refreshSymbolState (Resources { keyPress = Just (SpecialKey ENTER) })
    state@FrameState
      { nextSymbol = nextSymbol
      , currentFrame = currentFrame
      }
  | nextSymbol == "" = state
  | otherwise = state
    { currentSymbol = nextSymbol
    , nextSymbol = ""
    , currentFrame = newCurrentFrame (Chart nextSymbol)
    , previousFrame = newPreviousFrame currentFrame
    }

-- ESC cancels the next symbol.
refreshSymbolState (Resources { keyPress = Just (SpecialKey ESC) })
    state = state { nextSymbol = "" }

-- Drop all other events.
refreshSymbolState _ state = state

newCurrentFrame :: Content -> Maybe Frame
newCurrentFrame content = Just $ Frame
  { content = content
  , scaleAnimation = incomingScaleAnimation
  , alphaAnimation = incomingAlphaAnimation
  }

newPreviousFrame :: Maybe Frame -> Maybe Frame
newPreviousFrame Nothing = Nothing
newPreviousFrame (Just frame) = Just $ frame 
  { scaleAnimation = outgoingScaleAnimation
  , alphaAnimation = outgoingAlphaAnimation
  }

contentPadding = 10::GLfloat
cornerRadius = 10::GLfloat
cornerVertices = 5::Int

drawFrameBorder :: Resources -> IO ()
drawFrameBorder resources =
  drawRoundedRectangle width height cornerRadius cornerVertices
  where
     width = mainFrameWidth resources - contentPadding
     height = mainFrameHeight resources - contentPadding

drawCenteredInstructions :: Resources -> IO ()
drawCenteredInstructions resources = do
  layout <- createSimpleLayout
  setFontFaceSize (font resources) fontSize 72
  setLayoutFont layout (font resources)
  setLayoutLineLength layout layoutLineLength
  [left, bottom, _, right, top, _] <- getLayoutBBox layout instructions

  let textCenterX = -(left + (abs (right - left)) / 2)
      textCenterY = -(top - (abs (bottom - top)) / 2)
  preservingMatrix $ do 
    translate $ vector3 textCenterX textCenterY 0
    renderLayout layout instructions

  destroyLayout layout

  where
    fontSize = 18
    layoutLineLength = realToFrac $ mainFrameWidth resources - contentPadding
    instructions = "Type in symbol and press ENTER..."

drawCurrentSymbol :: Resources -> Content -> IO ()
drawCurrentSymbol resources (Chart symbol) = do
  layout <- createSimpleLayout
  setFontFaceSize (font resources) fontSize 72
  setLayoutFont layout (font resources)
  setLayoutLineLength layout layoutLineLength
  [left, bottom, _, right, top, _] <- getLayoutBBox layout symbol

  let textHeight = abs $ bottom - top
      textCenterX = -mainFrameWidth resources / 2 + symbolPadding
      textCenterY = mainFrameHeight resources / 2 - symbolPadding - textHeight
          
  preservingMatrix $ do 
    translate $ vector3 textCenterX textCenterY 0
    renderLayout layout symbol

  destroyLayout layout

  where
    fontSize = 18
    layoutLineLength = realToFrac $ mainFrameWidth resources - contentPadding
    symbolPadding = 15

drawNextSymbol :: Resources -> FrameState -> IO ()
drawNextSymbol _ (FrameState { nextSymbol = "" }) = return ()
drawNextSymbol resources (FrameState { nextSymbol = nextSymbol }) = do
  layout <- createSimpleLayout
  setFontFaceSize (font resources) fontSize 72
  setLayoutFont layout (font resources)
  setLayoutLineLength layout layoutLineLength
  [left, bottom, _, right, top, _] <- getLayoutBBox layout nextSymbol

  let textWidth = abs $ right - left
      textHeight = abs $ bottom - top

      textBubblePadding = 15
      textBubbleWidth = textWidth + textBubblePadding*2
      textBubbleHeight = textHeight + textBubblePadding*2

      textCenterX = -(left + textWidth / 2)
      textCenterY = -(top - textHeight / 2)

  -- Disable blending or else the background won't work.
  blend $= Disabled

  preservingMatrix $ do 
    color $ black 1
    fillRoundedRectangle textBubbleWidth textBubbleHeight
        cornerRadius cornerVertices

    color $ blue 1
    drawRoundedRectangle textBubbleWidth textBubbleHeight
        cornerRadius cornerVertices

    color $ green 1
    translate $ vector3 textCenterX textCenterY 0
    renderLayout layout nextSymbol

  blend $= Enabled

  destroyLayout layout

  where
    fontSize = 48
    layoutLineLength = realToFrac $ mainFrameWidth resources - contentPadding

