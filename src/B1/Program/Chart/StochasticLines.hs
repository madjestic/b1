module B1.Program.Chart.StochasticLines
  ( StochasticTimeSpec(..)
  , StochasticLineSpec(..)
  , getVboSpecs
  ) where

import Graphics.Rendering.OpenGL

import B1.Data.List
import B1.Data.Range
import B1.Data.Technicals.Stochastic
import B1.Data.Technicals.StockData
import B1.Graphics.Rendering.OpenGL.Box
import B1.Graphics.Rendering.OpenGL.Point
import B1.Graphics.Rendering.OpenGL.Shapes
import B1.Graphics.Rendering.OpenGL.Utils
import B1.Program.Chart.Animation
import B1.Program.Chart.Colors
import B1.Program.Chart.Dirty
import B1.Program.Chart.FragmentShader
import B1.Program.Chart.Resources
import B1.Program.Chart.StochasticColors
import B1.Program.Chart.Vbo

data StochasticLineSpec = StochasticLineSpec
  { timeSpec :: StochasticTimeSpec
  , lineColor :: Color3 GLfloat
  , stochasticFunction :: Stochastic -> Float
  }

data StochasticTimeSpec = Daily | Weekly

data DataStatus = Loading | Received

getVboSpecs :: StockPriceData -> [StochasticLineSpec] -> Box -> [VboSpec]
getVboSpecs priceData lineSpecs bounds =
  [getBackgroundVboSpec priceData lineSpecs bounds]
      ++ getLineVboSpecs priceData lineSpecs bounds

getBackgroundVboSpec :: StockPriceData -> [StochasticLineSpec] -> Box
    -> VboSpec
getBackgroundVboSpec priceData lineSpecs bounds = VboSpec Quads size elements
  where
    size = getBackgroundSize
    elements = getBackgroundElements priceData lineSpecs bounds

getBackgroundSize :: Int
getBackgroundSize = size
  where
    numQuads = 1
    verticesPerQuad = 4
    floatsPerVertex = 2 + 3 -- x, y, and 3 for color
    size = numQuads * (verticesPerQuad * floatsPerVertex)

getBackgroundElements :: StockPriceData -> [StochasticLineSpec] -> Box
    -> [GLfloat]
getBackgroundElements priceData lineSpecs bounds
  | null lineSpecs = []
  | null stochasticColors = []
  | otherwise = elements
  where
    dataFunction = case timeSpec (head lineSpecs) of
        Daily -> stochastics
        _ -> weeklyStochastics
    stochasticColors = getStochasticColors $ dataFunction priceData
    color = color3ToList $ head stochasticColors

    Box (left, top) (right, bottom) = bounds
    elements =
      -- Top Quad
      [ left
      , bottom
      , 0, 0, 0

      , left
      , top
      , 0, 0, 0

      , right
      , top
      , 0, 0, 0

      , right
      , bottom
      ] ++ color ++

      []

getLineVboSpecs :: StockPriceData -> [StochasticLineSpec] -> Box -> [VboSpec]
getLineVboSpecs priceData lineSpecs bounds =
  map (createLineVboSpec priceData bounds) lineSpecs

createLineVboSpec :: StockPriceData -> Box -> StochasticLineSpec -> VboSpec
createLineVboSpec priceData bounds lineSpec =
  VboSpec LineStrip size elements
  where
    size = getLineSize priceData lineSpec
    elements = createLine priceData bounds lineSpec

getLineSize :: StockPriceData -> StochasticLineSpec -> Int
getLineSize priceData lineSpec = size
  where
    numElementsFunction = case timeSpec lineSpec of
        Daily -> numDailyElements
        _ -> numWeeklyElements
    numElements = numElementsFunction priceData
    floatsPerVertex = 2 + 3 -- x, y, and 3 for color
    size = numElements * floatsPerVertex

createLine :: StockPriceData -> Box -> StochasticLineSpec -> [GLfloat]
createLine priceData bounds lineSpec =
  concat $ map (createLineSegment bounds color values) indices
  where
    color = lineColor lineSpec
    (dataFunction, numElements) = case timeSpec lineSpec of
        Daily -> (stochastics, numDailyElements)
        _ -> (weeklyStochastics, numWeeklyElements)
    values = map (stochasticFunction lineSpec) $
        take (numElements priceData) $
        dataFunction priceData
    indices = [0 .. length values - 1]

createLineSegment :: Box -> Color3 GLfloat -> [Float] -> Int -> [GLfloat]
createLineSegment bounds color values index = [x, y] ++ colorList
  where
    colorList = color3ToList color
    totalWidth = boxWidth bounds
    segmentWidth = realToFrac totalWidth / realToFrac (length values)
    x = boxRight bounds - realToFrac index * segmentWidth

    value = values !! index
    totalHeight = boxHeight bounds
    y = boxBottom bounds + realToFrac value * totalHeight

