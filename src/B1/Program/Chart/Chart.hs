module B1.Program.Chart.Chart
  ( ChartInput(..)
  , ChartOutput(..)
  , ChartState(stockData)
  , drawChart
  , newChartState
  , cleanChartState
  ) where

import Data.Maybe
import Data.Time.Calendar
import Data.Time.Clock
import Graphics.Rendering.FTGL
import Graphics.Rendering.OpenGL
import Text.Printf

import B1.Data.Range
import B1.Data.Symbol
import B1.Data.Technicals.Stochastic
import B1.Data.Technicals.StockData
import B1.Graphics.Rendering.FTGL.Utils
import B1.Graphics.Rendering.OpenGL.Box
import B1.Graphics.Rendering.OpenGL.Shapes
import B1.Graphics.Rendering.OpenGL.Utils
import B1.Program.Chart.Animation
import B1.Program.Chart.Colors
import B1.Program.Chart.Dirty
import B1.Program.Chart.Resources

import qualified B1.Program.Chart.Graph as G
import qualified B1.Program.Chart.GraphNumbers as GN
import qualified B1.Program.Chart.Header as H
import qualified B1.Program.Chart.StochasticLines as S
import qualified B1.Program.Chart.StochasticNumbers as SN
import qualified B1.Program.Chart.VolumeBars as V

data ChartInput = ChartInput
  { bounds :: Box
  , alpha :: GLfloat
  , symbol :: Symbol
  , inputState :: ChartState
  }

data ChartOutput = ChartOutput
  { outputState :: ChartState
  , isDirty :: Dirty
  , addedSymbol :: Maybe Symbol
  }

data ChartState = ChartState
  { stockData :: StockData
  , headerState :: H.HeaderState
  , graphState :: G.GraphState
  , volumeBarsState :: V.VolumeBarsState
  , stochasticsState :: S.StochasticLinesState
  , weeklyStochasticsState :: S.StochasticLinesState
  }

cleanChartState :: ChartState -> IO ChartState
cleanChartState
    state@ChartState
      { graphState = graphState
      , volumeBarsState = volumeBarsState
      , stochasticsState = stochasticsState
      , weeklyStochasticsState = weeklyStochasticsState
      } = do
  newGraphState <- G.cleanGraphState graphState
  newVolumeBarsState <- V.cleanVolumeBarsState volumeBarsState
  newStochasticsState <- S.cleanStochasticLinesState stochasticsState
  newWeeklyStochasticsState <- S.cleanStochasticLinesState
      weeklyStochasticsState
  return state
    { graphState = newGraphState
    , volumeBarsState = newVolumeBarsState
    , stochasticsState = newStochasticsState
    , weeklyStochasticsState = newStochasticsState
    }

newChartState :: Symbol -> IO ChartState
newChartState symbol = do
  stockData <- newStockData symbol
  return ChartState
    { stockData = stockData
    , headerState = H.newHeaderState H.LongStatus H.AddButton
    , graphState = G.newGraphState
    , volumeBarsState = V.newVolumeBarsState
    , stochasticsState = S.newStochasticLinesState dailySpecs
    , weeklyStochasticsState = S.newStochasticLinesState weeklySpecs
    }
  where
    dailySpecs =
      [ S.StochasticLineSpec 
        { S.timeSpec = S.Daily
        , S.lineColor = red3
        , S.stochasticFunction = k
        }
      , S.StochasticLineSpec
        { S.timeSpec = S.Daily
        , S.lineColor = yellow3
        , S.stochasticFunction = d
        }
      ]
    weeklySpecs =
      [ S.StochasticLineSpec 
        { S.timeSpec = S.Weekly
        , S.lineColor = red3
        , S.stochasticFunction = k
        }
      , S.StochasticLineSpec
        { S.timeSpec = S.Weekly
        , S.lineColor = purple3
        , S.stochasticFunction = d
        }
      ]

drawChart :: Resources -> ChartInput -> IO ChartOutput
drawChart resources
    input@ChartInput
      { bounds = bounds
      , alpha = alpha
      , symbol = symbol
      , inputState = inputState@ChartState
        { stockData = stockData
        , headerState = headerState
        , graphState = graphState
        , volumeBarsState = volumeBarsState
        , stochasticsState = stochasticsState
        , weeklyStochasticsState = weeklyStochasticsState
        }
      } = do
  (newHeaderState, headerDirty, addedSymbol, headerHeight)
      <- drawHeader resources alpha symbol stockData headerState bounds
  boundsSet <- getBounds resources bounds headerHeight stockData

  (newGraphState, graphDirty) <- preservingMatrix $ do
    let subBounds = graphBounds boundsSet
    translateToCenter bounds subBounds
    drawGraph resources alpha stockData graphState subBounds

  (newVolumeBarsState, volumeBarsDirty) <- preservingMatrix $ do
    let subBounds = volumeBarsBounds boundsSet
    translateToCenter bounds subBounds
    drawVolumeBars resources alpha stockData volumeBarsState subBounds

  (newStochasticsState, stochasticsDirty) <- preservingMatrix $ do
    let subBounds = stochasticsBounds boundsSet
    translateToCenter bounds subBounds
    drawStochasticLines resources alpha stockData
        stochasticsState subBounds

  (newWeeklyStochasticsState, weeklyStochasticsDirty) <- preservingMatrix $ do
    let subBounds = weeklyStochasticsBounds boundsSet
    translateToCenter bounds subBounds
    drawStochasticLines resources alpha stockData
        weeklyStochasticsState subBounds

  preservingMatrix $ do
    let subBounds = graphNumbersBounds boundsSet
    translateToCenter bounds subBounds
    drawGraphNumbers resources alpha GN.Prices stockData subBounds

  preservingMatrix $ do
    let subBounds = volumeBarNumbersBounds boundsSet
    translateToCenter bounds subBounds
    drawGraphNumbers resources alpha GN.Volume stockData subBounds

  preservingMatrix $ do
    let subBounds = stochasticNumbersBounds boundsSet
    translateToCenter bounds subBounds
    drawStochasticNumbers resources alpha subBounds

  preservingMatrix $ do
    let subBounds = weeklyStochasticNumbersBounds boundsSet
    translateToCenter bounds subBounds
    drawStochasticNumbers resources alpha subBounds

  preservingMatrix $ do
    drawDividerLines resources alpha bounds boundsSet headerHeight

  return ChartOutput
    { outputState = inputState
      { headerState = newHeaderState
      , graphState = newGraphState
      , volumeBarsState = newVolumeBarsState
      , stochasticsState = newStochasticsState
      , weeklyStochasticsState = newWeeklyStochasticsState
      }
    , isDirty = headerDirty
        || graphDirty
        || volumeBarsDirty
        || stochasticsDirty
        || weeklyStochasticsDirty
    , addedSymbol = addedSymbol
    }

drawHeader :: Resources -> GLfloat -> Symbol -> StockData -> H.HeaderState -> Box
    -> IO (H.HeaderState, Dirty, Maybe Symbol, GLfloat)
drawHeader resources alpha symbol stockData headerState bounds = do
  let headerInput = H.HeaderInput
        { H.bounds = bounds
        , H.fontSize = 18
        , H.padding = 10
        , H.alpha = alpha
        , H.symbol = symbol
        , H.stockData = stockData
        , H.inputState = headerState
        }

  headerOutput <- H.drawHeader resources headerInput 

  let H.HeaderOutput
        { H.outputState = outputHeaderState
        , H.isDirty = isHeaderDirty
        , H.height = headerHeight
        , H.clickedSymbol = addedSymbol
        } = headerOutput
  return (outputHeaderState, isHeaderDirty, addedSymbol, headerHeight)

data Bounds = Bounds
  { graphBounds :: Box
  , graphNumbersBounds :: Box
  , volumeBarsBounds :: Box
  , volumeBarNumbersBounds :: Box
  , stochasticsBounds :: Box
  , stochasticNumbersBounds :: Box
  , weeklyStochasticsBounds :: Box
  , weeklyStochasticNumbersBounds :: Box
  }

getBounds :: Resources -> Box -> GLfloat -> StockData -> IO Bounds
getBounds resources bounds headerHeight stockData = do
  graphNumbersWidth <- GN.getPreferredWidth resources GN.Prices stockData
  volumeBarNumbersWidth <- GN.getPreferredWidth resources GN.Volume stockData
  stochasticNumbersWidth <- SN.getPreferredWidth resources
  let minNumbersWidth = maximum
        [ graphNumbersWidth
        , volumeBarNumbersWidth
        , stochasticNumbersWidth
        ]
      numbersLeft = right - minNumbersWidth

      Box (left, top) (right, bottom) = bounds
      bottomPadding = 20
      remainingHeight = boxHeight bounds - headerHeight - bottomPadding
      graphHeight = remainingHeight * 0.55
      volumeBarsHeight = (remainingHeight - graphHeight) / 3
      stochasticsHeight = volumeBarsHeight
      weeklyStochasticsHeight = remainingHeight - graphHeight
          - volumeBarsHeight - stochasticsHeight

      graphBounds = Box (left, top - headerHeight)
          (numbersLeft, top - headerHeight - graphHeight)
      graphNumbersBounds = Box
          (numbersLeft, boxTop graphBounds)
          (right, boxBottom graphBounds)

      volumeBarsBounds = Box (left, boxBottom graphBounds)
          (numbersLeft, boxBottom graphBounds - volumeBarsHeight)
      volumeBarNumbersBounds = Box
          (numbersLeft, boxTop volumeBarsBounds)
          (right, boxBottom volumeBarsBounds)

      stochasticsBounds = Box
          (left, boxBottom volumeBarsBounds)
          (numbersLeft, boxBottom volumeBarsBounds - stochasticsHeight)
      stochasticNumbersBounds = Box
          (numbersLeft, boxTop stochasticsBounds)
          (right, boxBottom stochasticsBounds)

      weeklyStochasticsBounds = Box
          (left, boxBottom stochasticsBounds)
          (numbersLeft, boxBottom stochasticsBounds - weeklyStochasticsHeight)
      weeklyStochasticNumbersBounds = Box
          (numbersLeft, boxTop weeklyStochasticsBounds)
          (right, boxBottom weeklyStochasticsBounds)

  return Bounds
    { graphBounds = graphBounds
    , graphNumbersBounds = graphNumbersBounds
    , volumeBarsBounds = volumeBarsBounds
    , volumeBarNumbersBounds = volumeBarNumbersBounds
    , stochasticsBounds = stochasticsBounds
    , stochasticNumbersBounds = stochasticNumbersBounds
    , weeklyStochasticsBounds = weeklyStochasticsBounds
    , weeklyStochasticNumbersBounds = weeklyStochasticNumbersBounds
    }

-- Starts translating from the center of outerBounds
translateToCenter :: Box -> Box -> IO ()
translateToCenter outerBounds innerBounds =
  translate $ vector3 translateX translateY 0
  where
    translateX = -(boxWidth outerBounds / 2) -- Goto left of outer
        + (boxRight innerBounds - boxLeft outerBounds) -- Goto right of inner 
        - (boxWidth innerBounds / 2) -- Go back half of inner
    translateY = -(boxHeight outerBounds / 2) -- Goto bottom of outer
        + (boxTop innerBounds - boxBottom outerBounds) -- Goto top of inner
        - (boxHeight innerBounds / 2) -- Go down half of inner

drawGraph :: Resources -> GLfloat -> StockData -> G.GraphState -> Box
    -> IO (G.GraphState, Dirty)
drawGraph resources alpha stockData graphState bounds = do
  let graphInput = G.GraphInput
        { G.bounds = boxShrink 1 bounds
        , G.alpha = alpha
        , G.stockData = stockData
        , G.inputState = graphState
        }

  graphOutput <- G.drawGraph resources graphInput

  let G.GraphOutput
        { G.outputState = outputGraphState
        , G.isDirty = isGraphDirty
        } = graphOutput
  return (outputGraphState, isGraphDirty)

drawVolumeBars :: Resources -> GLfloat -> StockData -> V.VolumeBarsState -> Box
    -> IO (V.VolumeBarsState, Dirty)
drawVolumeBars resources alpha stockData volumeBarsState bounds = do
  let volumeBarsInput = V.VolumeBarsInput
        { V.bounds = boxShrink 1 bounds
        , V.alpha = alpha
        , V.stockData = stockData
        , V.inputState = volumeBarsState
        }

  volumeBarsOutput <- V.drawVolumeBars resources volumeBarsInput

  let V.VolumeBarsOutput
        { V.outputState = outputVolumeBarsState
        , V.isDirty = isVolumeDirty
        } = volumeBarsOutput
  return (outputVolumeBarsState, isVolumeDirty)

drawStochasticLines :: Resources -> GLfloat -> StockData
    -> S.StochasticLinesState -> Box -> IO (S.StochasticLinesState, Dirty)
drawStochasticLines resources alpha stockData stochasticsState bounds = do
  let stochasticsInput = S.StochasticLinesInput
        { S.bounds = boxShrink 1 bounds
        , S.alpha = alpha
        , S.stockData = stockData
        , S.inputState = stochasticsState
        }

  stochasticsOutput <- S.drawStochasticLines resources stochasticsInput

  let S.StochasticLinesOutput
        { S.outputState = outputStochasticsState
        , S.isDirty = isStochasticsDirty
        } = stochasticsOutput
  return (outputStochasticsState, isStochasticsDirty)

drawGraphNumbers :: Resources -> GLfloat -> GN.GraphNumbersType -> StockData
    -> Box -> IO ()
drawGraphNumbers resources alpha numbersType stockData bounds = do
  let numbersInput = GN.GraphNumbersInput
        { GN.bounds = bounds
        , GN.alpha = alpha
        , GN.stockData = stockData
        , GN.numbersType = numbersType
        }
  GN.drawGraphNumbers resources numbersInput

drawStochasticNumbers :: Resources -> GLfloat -> Box -> IO ()
drawStochasticNumbers resources alpha bounds = do
  let numbersInput = SN.StochasticNumbersInput
        { SN.bounds = bounds
        , SN.alpha = alpha
        }
  SN.drawStochasticNumbers resources numbersInput

drawDividerLines :: Resources -> GLfloat -> Box -> Bounds -> GLfloat -> IO ()
drawDividerLines resources alpha bounds
    Bounds
      { graphBounds = graphBounds
      , volumeBarsBounds = volumeBarsBounds
      , stochasticsBounds = stochasticsBounds
      , weeklyStochasticsBounds = weeklyStochasticsBounds
      }
    headerHeight = do
  lineWidth $= 1
  color $ outlineColor resources bounds alpha

  preservingMatrix $ do
    translate $ vector3 0 headerOffset 0
    drawHorizontalRule $ boxWidth bounds - 1

    translate $ vector3 horizontalGraphOffset 0 0
    mapM_ translateDrawGraphRule
        [ bottomGraphOffset
        , bottomVolumeBarsOffset
        , bottomStochasticsOffset
        , bottomWeeklyStochasticsOffset
        ]

  preservingMatrix $ do
    translateToCenter bounds verticalBounds
    drawVerticalRule verticalHeight

  where
    headerOffset = boxHeight bounds / 2 - headerHeight
    bottomGraphOffset = -boxHeight graphBounds
    bottomVolumeBarsOffset = -boxHeight volumeBarsBounds
    bottomStochasticsOffset = -boxHeight stochasticsBounds
    bottomWeeklyStochasticsOffset = -boxHeight weeklyStochasticsBounds

    horizontalGraphRuleWidth = boxWidth graphBounds
    horizontalGraphOffset = -(boxWidth bounds / 2)
        + horizontalGraphRuleWidth / 2

    verticalCenter = boxLeft graphBounds + boxWidth graphBounds
    verticalBounds = Box (verticalCenter, boxTop graphBounds)
        (verticalCenter, boxBottom weeklyStochasticsBounds)

    verticalHeight = sum $ map boxHeight
        [ graphBounds
        , volumeBarsBounds
        , stochasticsBounds
        , weeklyStochasticsBounds
        ]
    verticalXOffset = -(boxWidth bounds / 2) + boxWidth graphBounds
    verticalYOffset = boxHeight bounds / 2 - headerHeight - verticalHeight / 2

    translateDrawGraphRule :: GLfloat -> IO ()
    translateDrawGraphRule offset = do
      translate $ vector3 0 offset 0
      drawHorizontalRule horizontalGraphRuleWidth

