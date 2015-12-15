---------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.Plugin.Env
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- The environment for mapping concrete functions/types to symbolic ones.
-----------------------------------------------------------------------------

{-# LANGUAGE MagicHash       #-}
{-# LANGUAGE TemplateHaskell #-}

module Data.SBV.Plugin.Env (buildTCEnv, buildFunEnv, buildDests) where

import GhcPlugins
import GHC.Prim
import GHC.Types

import qualified Data.Map            as M
import qualified Language.Haskell.TH as TH

import Data.Int
import Data.Word
import Data.Bits
import Data.Maybe (fromMaybe)
import Data.Ratio

import qualified Data.SBV         as S hiding (proveWith, proveWithAny)
import qualified Data.SBV.Dynamic as S

import Data.SBV.Plugin.Common

-- | Build the initial environment containing types
buildTCEnv :: Int -> CoreM (M.Map (TyCon, [TyCon]) S.Kind)
buildTCEnv wsz = do xs <- mapM grabTyCon basics
                    ys <- mapM grabTyApp apps
                    return $ M.fromList $ xs ++ ys

  where grab x = do Just fn <- thNameToGhcName x
                    lookupTyCon fn

        grabTyCon (x, k) = grabTyApp (x, [], k)

        grabTyApp (x, as, k) = do fn   <- grab x
                                  args <- mapM grab as
                                  return ((fn, args), k)

        basics = concat [ [(t, S.KBool)              | t <- [''Bool              ]]
                        , [(t, S.KUnbounded)         | t <- [''Integer           ]]
                        , [(t, S.KFloat)             | t <- [''Float,   ''Float# ]]
                        , [(t, S.KDouble)            | t <- [''Double,  ''Double#]]
                        , [(t, S.KBounded True  wsz) | t <- [''Int,     ''Int#   ]]
                        , [(t, S.KBounded True    8) | t <- [''Int8              ]]
                        , [(t, S.KBounded True   16) | t <- [''Int16             ]]
                        , [(t, S.KBounded True   32) | t <- [''Int32,   ''Int32# ]]
                        , [(t, S.KBounded True   64) | t <- [''Int64,   ''Int64# ]]
                        , [(t, S.KBounded False wsz) | t <- [''Word,    ''Word#  ]]
                        , [(t, S.KBounded False   8) | t <- [''Word8             ]]
                        , [(t, S.KBounded False  16) | t <- [''Word16            ]]
                        , [(t, S.KBounded False  32) | t <- [''Word32,  ''Word32#]]
                        , [(t, S.KBounded False  64) | t <- [''Word64,  ''Word64#]]
                        ]

        apps =  [ (''Ratio, [''Integer], S.KReal) ]

-- | Build the initial environment containing functions
buildFunEnv :: Int -> CoreM (M.Map (Id, SKind) Val)
buildFunEnv wsz = M.fromList `fmap` mapM thToGHC (basicFuncs wsz ++ symFuncs)

-- | Basic conversions, only on one kind
basicFuncs :: Int -> [(TH.Name, SKind, Val)]
basicFuncs wsz = [ ('F#,    tlift1 S.KFloat,               Func  Nothing return)
                 , ('D#,    tlift1 S.KDouble,              Func  Nothing return)
                 , ('I#,    tlift1 $ S.KBounded True  wsz, Func  Nothing return)
                 , ('W#,    tlift1 $ S.KBounded False wsz, Func  Nothing return)
                 , ('True,  KBase S.KBool,                 Base  S.svTrue)
                 , ('False, KBase S.KBool,                 Base  S.svFalse)
                 , ('(&&),  tlift2 S.KBool,                lift2 S.svAnd)
                 , ('(||),  tlift2 S.KBool,                lift2 S.svOr)
                 , ('not,   tlift1 S.KBool,                lift1 S.svNot)
                 ]

-- | Symbolic functions supported by the plugin; those from a class.
symFuncs :: [(TH.Name, SKind, Val)]
symFuncs =  -- equality is for all kinds
          [(op, tlift2Bool k, lift2 sOp) | k <- allKinds, (op, sOp) <- [('(==), S.svEqual), ('(/=), S.svNotEqual)]]

          -- arithmetic
       ++ [(op, tlift1 k, lift1 sOp) | k <- arithKinds, (op, sOp) <- unaryOps]
       ++ [(op, tlift2 k, lift2 sOp) | k <- arithKinds, (op, sOp) <- binaryOps]

          -- literal conversions from Integer
       ++ [(op, KFun S.KUnbounded (KBase k), lift1Int sOp) | k <- integerKinds, (op, sOp) <- [('fromInteger, S.svInteger k)]]

          -- comparisons
       ++ [(op, tlift2Bool k, lift2 sOp) | k <- arithKinds, (op, sOp) <- compOps ]

          -- integer div/rem
      ++ [(op, tlift2 k, lift2 sOp) | k <- integralKinds, (op, sOp) <- [('div, S.svDivide), ('quot, S.svQuot), ('rem, S.svRem)]]

         -- bit-vector
      ++ [ (op, tlift2 k, lift2 sOp) | k <- bvKinds, (op, sOp) <- bvBinOps]

 where
       -- Bit-vectors
       bvKinds    = [S.KBounded s sz | s <- [False, True], sz <- [8, 16, 32, 64]]

       -- Those that are "integral"ish
       integralKinds = S.KUnbounded : bvKinds

       -- Those that can be converted from an Integer
       integerKinds = S.KReal : integralKinds

       -- Float kinds
       floatKinds = [S.KFloat, S.KDouble]

       -- All arithmetic kinds
       arithKinds = floatKinds ++ integerKinds

       -- Everything
       allKinds   = S.KBool : arithKinds

       -- Unary arithmetic ops
       unaryOps   = [ ('abs,    S.svAbs)
                    , ('negate, S.svUNeg)
                    ]

       -- Binary arithmetic ops
       binaryOps  = [ ('(+), S.svPlus)
                    , ('(-), S.svMinus)
                    , ('(*), S.svTimes)
                    , ('(/), S.svDivide)
                    ]

       -- Comparisons
       compOps = [ ('(<),  S.svLessThan)
                 , ('(>),  S.svGreaterThan)
                 , ('(<=), S.svLessEq)
                 , ('(>=), S.svGreaterEq)
                 ]

       -- Binary bit-vector ops
       bvBinOps = [ ('(.&.), S.svAnd)
                  , ('(.|.), S.svOr)
                  , ('xor,   S.svXOr)
                  ]


-- | Destructors
buildDests :: Int -> CoreM (M.Map (Var, SKind) (S.SVal -> [Var] -> (S.SVal, [((Var, SKind), Val)])))
buildDests wsz = M.fromList `fmap` mapM thToGHC dests
  where dests = [ unbox 'W# (S.KBounded False wsz)
                , unbox 'I# (S.KBounded True  wsz)
                , unbox 'F# S.KFloat
                , unbox 'D# S.KDouble
                ]

        unbox a k     = (a, tlift1 k, dest1 k)
        dest1 k a [b] = (S.svTrue, [((b, KBase k), Base a)])
        dest1 _ a bs  = error $ "Impossible happened: Mistmatched arity case-binder for: " ++ show a ++ ". Expected 1, got: " ++ show (length bs) ++ " arguments."

-- | Lift a binary type, with result bool
tlift2Bool :: S.Kind -> SKind
tlift2Bool k = KFun k (KFun k (KBase S.KBool))

-- | Lift a binary type
tlift2 :: S.Kind -> SKind
tlift2 k = KFun k (KFun k (KBase k))

-- | Lift a unary type
tlift1 :: S.Kind -> SKind
tlift1 k = KFun k (KBase k)

-- | Lift a unary SBV function that via kind/integer
lift1Int :: (Integer -> S.SVal) -> Val
lift1Int f = Func Nothing g
   where g (Base i) = return $ Base $ f (fromMaybe (error ("Cannot extract an integer from value: " ++ show i)) (S.svAsInteger i))
         g _        = error "Impossible happened: lift1Int received non-base argument!"

-- | Lift a unary SBV function to the plugin value space
lift1 :: (S.SVal -> S.SVal) -> Val
lift1 f = Func Nothing g
  where g (Typ _)  = return $ Func Nothing h
        g v        = h v
        h (Base a) = return $ Base $ f a
        h _        = error "Impossible happened: lift1 received non-base argument!"

-- | Lift a two argument SBV function to our the plugin value space
lift2 :: (S.SVal -> S.SVal -> S.SVal) -> Val
lift2 f = Func Nothing g
   where g (Typ  _)   = return $ Func Nothing h
         g v          = h v
         h   (Base a) = return $ Func Nothing (k a)
         h _          = error "Impossible happened: lift2 received non-base argument (h)!"
         k a (Base b) = return $ Base $ f a b
         k _ _        = error "Impossible happened: lift2 received non-base argument (k)!"

thToGHC :: (TH.Name, a, b) -> CoreM ((Id, a), b)
thToGHC (n, k, sfn) = do mbFN <- thNameToGhcName n
                         case mbFN of
                           Just fn  -> do f <- lookupId fn
                                          return ((f, k), sfn)
                           Nothing -> error $ "[SBV] Impossible happened, while trying to locate GHC name for: " ++ show n
