-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.Plugin.Examples.BitTricks
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- Checks the correctness of a few tricks from the large collection found in:
--      <http://graphics.stanford.edu/~seander/bithacks.html>
-----------------------------------------------------------------------------

{-# OPTIONS_GHC -fplugin=Data.SBV.Plugin #-}

module Data.SBV.Plugin.Examples.BitTricks where

import Data.SBV.Plugin

import Data.Bits
import Data.Word

import Prelude hiding(elem)

-- | SBVPlugin can only see definitions in the current module. So we define `elem` ourselves.
elem :: Eq a => a -> [a] -> Bool
elem _ []     = False
elem k (x:xs) = k == x || elem k xs

-- | Returns 1 if bool is @True@
oneIf :: Num a => Bool -> a
oneIf True  = 1
oneIf False = 0

-- | Formalizes <http://graphics.stanford.edu/~seander/bithacks.html#IntegerMinOrMax>
{-# ANN fastMinCorrect theorem #-}
fastMinCorrect :: Int -> Int -> Bool
fastMinCorrect x y = m == fm
  where m  = if x < y then x else y
        fm = y `xor` ((x `xor` y) .&. (-(oneIf (x < y))));

-- | Formalizes <http://graphics.stanford.edu/~seander/bithacks.html#IntegerMinOrMax>
{-# ANN fastMaxCorrect theorem #-}
fastMaxCorrect :: Int -> Int -> Bool
fastMaxCorrect x y = m == fm
  where m  = if x < y then y else x
        fm = x `xor` ((x `xor` y) .&. (-(oneIf (x < y))));

-- | Formalizes <http://graphics.stanford.edu/~seander/bithacks.html#DetectOppositeSigns>
{-# ANN oppositeSignsCorrect theorem #-}
oppositeSignsCorrect :: Int -> Int -> Bool
oppositeSignsCorrect x y = r == os
  where r  = (x < 0 && y >= 0) || (x >= 0 && y < 0)
        os = (x `xor` y) < 0

-- | Formalizes <http://graphics.stanford.edu/~seander/bithacks.html#ConditionalSetOrClearBitsWithoutBranching>
{-# ANN conditionalSetClearCorrect theorem #-}
conditionalSetClearCorrect :: Bool -> Word32 -> Word32 -> Bool
conditionalSetClearCorrect f m w = r == r'
  where r  | f    = w .|. m
           | True = w .&. complement m
        r' = w `xor` ((-(oneIf f) `xor` w) .&. m)

-- | Formalizes <http://graphics.stanford.edu/~seander/bithacks.html#DetermineIfPowerOf2>
{-# ANN powerOfTwoCorrect theorem #-}
powerOfTwoCorrect :: Word32 -> Bool
powerOfTwoCorrect v = f == (v `elem` powers)
  where f = (v /= 0) && ((v .&. (v-1)) == 0)

        powers :: [Word32]
        powers = [        1,        2,        4,         8,        16,        32,         64,        128
                 ,      256,      512,     1024,      2048,      4096,      8192,      16384,      32768
                 ,    65536,   131072,   262144,    524288,   1048576,   2097152,    4194304,    8388608
                 , 16777216, 33554432, 67108864, 134217728, 268435456, 536870912, 1073741824, 2147483648
                 ]
