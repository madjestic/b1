module B1.Graphics.Rendering.OpenGL.Box
  ( Box(..)
  , boxCenter
  , boxContains
  , boxContainsBox
  , boxShrink
  , boxSize
  , boxLeft
  , boxTop
  , boxRight
  , boxBottom
  , boxWidth
  , boxHeight
  , createBox
  , zeroBox
  ) where

import Graphics.Rendering.OpenGL

import B1.Graphics.Rendering.OpenGL.Point
import B1.Graphics.Rendering.OpenGL.Utils

data Box = 
  -- | Construct a box from upper left and bottom right points.  
  Box Point Point 
  deriving (Show)

boxCenter :: Box -> Point
boxCenter box@(Box (left, top) _) = (centerX, centerY)
  where
    centerX = left + boxWidth box / 2
    centerY = top - boxHeight box / 2

-- TODO: Rename to boxContainsPoint
boxContains :: Box -> Point -> Bool
boxContains (Box (left, top) (right, bottom)) (x, y) =
  x >= left && x <= right && y <= top && y >= bottom

boxContainsBox :: Box -> Box -> Bool
boxContainsBox (Box (parentLeft, parentTop) (parentRight, parentBottom))
    (Box (childLeft, childTop) (childRight, childBottom)) =
  parentLeft <= childLeft
      && parentRight >= childRight
      && parentTop >= childTop
      && parentBottom <= childBottom

boxSize :: Box -> (GLfloat, GLfloat)
boxSize box = (boxWidth box, boxHeight box)

boxShrink :: GLfloat -> Box -> Box
boxShrink shrink (Box (left, top) (right, bottom)) =
  Box (left + shrink, top - shrink) (right - shrink, bottom + shrink)

boxLeft :: Box -> GLfloat
boxLeft (Box (left, _) (_, _)) = left

boxTop :: Box -> GLfloat
boxTop (Box (_, top) (_, _)) = top

boxRight :: Box -> GLfloat
boxRight (Box (_, _) (right, _)) = right

boxBottom :: Box -> GLfloat
boxBottom (Box (_, _) (_, bottom)) = bottom

boxWidth :: Box -> GLfloat
boxWidth (Box (left, _) (right, _)) = abs $ right - left

boxHeight :: Box -> GLfloat
boxHeight (Box (_, top) (_, bottom)) = abs $ bottom - top

createBox :: GLfloat -> GLfloat -> Point -> Box
createBox width height (x, y) = 
  Box (x - halfWidth, y + halfHeight) (x + halfWidth, y - halfHeight)
  where
    halfWidth = width / 2
    halfHeight = height / 2

zeroBox :: Box
zeroBox = Box (0, 0) (0, 0)

