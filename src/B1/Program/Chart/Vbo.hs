module B1.Program.Chart.Vbo
  ( Vbo
  , VboSpec(..)
  , createVbo
  , renderVbo
  , deleteVbo
  ) where

import Control.Concurrent
import Control.Concurrent.MVar
import Control.Monad
import Data.Array.Storable
import Debug.Trace
import Foreign.Marshal.Array
import Foreign.Ptr
import Foreign.Storable
import Graphics.Rendering.OpenGL

import B1.Control.TaskManager
import B1.Graphics.Rendering.OpenGL.BufferManager
import B1.Program.Chart.Resources

type NumElements = Int

data Vbo = Vbo
  { bufferObject :: BufferObject
  , unmapMVar :: MVar Bool
  , primitiveGroups :: [(PrimitiveMode, NumElements)]
  }

type ArraySize = Int

data VboSpec = VboSpec PrimitiveMode ArraySize [GLfloat]

createVbo :: Resources -> [VboSpec] -> IO Vbo
createVbo resources vboSpecs = do
  bufferObject <- getOrCreateBindedBuffer (bufferManager resources) numBytes
  maybePtr <- mapBuffer ArrayBuffer WriteOnly
  bindBuffer ArrayBuffer $= Nothing
  
  unmapMVar <- newEmptyMVar
  case maybePtr of
    Just ptr -> do
      addTask (taskManager resources) $ do
        let allElements = concat $
                map (\(VboSpec _ _ elements) -> elements) vboSpecs
        pokeArray ptr allElements
        putMVar unmapMVar True
        traceIO $ "VBO Estimated size: " ++ show numBytes
            ++ " Real size: " ++ show (length allElements * 4)
    _ -> error "Couldn't map buffer..."

  return Vbo
    { bufferObject = bufferObject
    , unmapMVar = unmapMVar
    , primitiveGroups = primitiveGroups
    }
  where
    totalSize = sum $ map (\(VboSpec _ size _) -> size) vboSpecs
    numBytes = toEnum $ totalSize * 4
    primitiveGroups = map
        (\(VboSpec primitiveMode size _) -> (primitiveMode, size `div` 5))
        vboSpecs

deleteVbo :: Resources -> Vbo -> IO ()
deleteVbo resources
    Vbo
      { bufferObject = bufferObject
      , unmapMVar = unmapMVar
      } = do
  unmap <- takeMVar unmapMVar
  unmapIfNecessary unmap bufferObject
  recycleBuffer (bufferManager resources) bufferObject

unmapIfNecessary :: Bool -> BufferObject -> IO ()
unmapIfNecessary unmap bufferObject = do
  bindBuffer ArrayBuffer $= Just bufferObject
  when unmap $ do
    unmapBuffer ArrayBuffer
    return ()
  bindBuffer ArrayBuffer $= Nothing

renderVbo :: Vbo -> IO Bool
renderVbo
    Vbo
      { bufferObject = bufferObject
      , unmapMVar = unmapMVar
      , primitiveGroups = primitiveGroups
      } = do
  maybeUnmap <- tryTakeMVar unmapMVar
  case maybeUnmap of
    Just unmap -> do
      tryPutMVar unmapMVar False
      unmapIfNecessary unmap bufferObject

      bindBuffer ArrayBuffer $= Just bufferObject
      arrayPointer VertexArray $= vertexArrayDescriptor
      arrayPointer ColorArray $= colorArrayDescriptor
      renderPrimitiveGroups primitiveGroups
      bindBuffer ArrayBuffer $= Nothing

      return True
    _ ->
      return False
  where
    vertexArrayDescriptor = VertexArrayDescriptor 2 Float 20 $ offset 0
    colorArrayDescriptor = VertexArrayDescriptor 3 Float 20 $ offset 8

renderPrimitiveGroups :: [(PrimitiveMode, NumElements)] -> IO ()
renderPrimitiveGroups primitiveGroups =
  mapM_ (\(offset, (primitiveMode, numElements)) ->
      drawArrays primitiveMode (fromIntegral offset) (fromIntegral numElements)
      ) (zip offsets primitiveGroups)
  where
    offsets = scanl (+) 0 $ map snd primitiveGroups

offset x = plusPtr nullPtr x

