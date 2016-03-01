{-# LANGUAGE ForeignFunctionInterface #-}
module Internal.Arm64 where

#include <capstone/arm64.h>

{#context lib = "capstone"#}

import Control.Monad (join)

import Foreign
import Foreign.C.Types

{#enum arm64_shifter as Arm64Shifter {underscoreToCase} deriving (Show)#}
{#enum arm64_extender as Arm64Extender {underscoreToCase} deriving (Show)#}
{#enum arm64_cc as Arm64ConditionCode {underscoreToCase} deriving (Show)#}

{#enum arm64_sysreg as Arm64Sysreg {underscoreToCase} deriving (Show)#}
{#enum arm64_msr_reg as Arm64MsrReg {underscoreToCase} deriving (Show)#}

{#enum arm64_pstate as Arm64Pstate {underscoreToCase} deriving (Show)#}

{#enum arm64_vas as Arm64Vas {underscoreToCase} deriving (Show)#}
{#enum arm64_vess as Arm64Vess {underscoreToCase} deriving (Show)#}

{#enum arm64_barrier_op as Arm64BarrierOp {underscoreToCase} deriving (Show)#}
{#enum arm64_op_type as Arm64OpType {underscoreToCase} deriving (Show)#}
{#enum arm64_tlbi_op as Arm64TlbiOp {underscoreToCase} deriving (Show)#}
{#enum arm64_at_op as Arm64AtOp {underscoreToCase} deriving (Show)#}
{#enum arm64_dc_op as Arm64DcOp {underscoreToCase} deriving (Show)#}
{#enum arm64_ic_op as Arm64IcOp {underscoreToCase} deriving (Show)#}
{#enum arm64_prefetch_op as Arm64PrefetchOp
    {underscoreToCase} deriving (Show)#}

data Arm64OpMemStruct = Arm64OpMemStruct Word32 Word32 Int32

instance Storable Arm64OpMemStruct where
    sizeOf _ = {#sizeof arm64_op_mem#}
    alignment _ = {#alignof arm64_op_mem#}
    peek p = Arm64OpMemStruct
        <$> (fromIntegral <$> {#get arm64_op_mem->base#} p)
        <*> (fromIntegral <$> {#get arm64_op_mem->index#} p)
        <*> (fromIntegral <$> {#get arm64_op_mem->disp#} p)
    poke p (Arm64OpMemStruct b i d) = do
        {#set arm64_op_mem->base#} p (fromIntegral b)
        {#set arm64_op_mem->index#} p (fromIntegral i)
        {#set arm64_op_mem->disp#} p (fromIntegral d)

data CsArm64OpValue
    = Reg Word32
    | Imm Int64
    | CImm Int64
    | Fp Double
    | Mem Arm64OpMemStruct
    | Pstate Arm64Pstate
    | Sys Word32
    | Prefetch Arm64PrefetchOp
    | Barrier Arm64BarrierOp
    | Undefined

data CsArm64Op = CsArm64Op
    { vectorIndex :: Int32
    , vas :: Arm64Vas
    , vess :: Arm64Vess
    , shift :: (Arm64Shifter, Word32)
    , ext :: Arm64Extender
    , value :: CsArm64OpValue
    }

instance Storable CsArm64Op where
    sizeOf _ = {#sizeof cs_arm64_op#}
    alignment _ = {#alignof cs_arm64_op#}
    peek p = CsArm64Op
        <$> (fromIntegral <$> {#get cs_arm64_op->vector_index#} p)
        <*> ((toEnum . fromIntegral) <$> {#get cs_arm64_op->vas#} p)
        <*> ((toEnum . fromIntegral) <$> {#get cs_arm64_op->vess#} p)
        <*> ((,) <$>
            ((toEnum . fromIntegral) <$> {#get cs_arm64_op->shift.type#} p) <*>
            (fromIntegral <$> {#get cs_arm64_op->shift.value#} p))
        <*> ((toEnum . fromIntegral) <$> {#get cs_arm64_op->ext#} p)
        <*> do
            t <- fromIntegral <$> {#get cs_arm64_op->type#} p :: IO Int
            let bP = plusPtr p -- FIXME: maybe alignment will bite us!
                   ({#offsetof cs_arm64_op.type#} + {#sizeof arm64_op_type#})
            case toEnum t :: Arm64OpType of
              Arm64OpReg -> (Reg . fromIntegral) <$> (peek bP :: IO CUInt)
              Arm64OpImm -> (Imm . fromIntegral) <$> (peek bP :: IO Int64)
              Arm64OpCimm -> (CImm . fromIntegral) <$> (peek bP :: IO Int64)
              Arm64OpFp -> (Fp . realToFrac) <$> (peek bP :: IO CDouble)
              Arm64OpMem -> Mem <$> (peek bP :: IO Arm64OpMemStruct)
              Arm64OpRegMsr -> (Pstate . toEnum . fromIntegral) <$>
                 (peek bP :: IO CInt) -- FIXME: is this the right type?
              Arm64OpSys -> (Sys . fromIntegral) <$> (peek bP :: IO CUInt)
              Arm64OpPrefetch -> (Prefetch . toEnum . fromIntegral) <$>
                 (peek bP :: IO CInt) -- FIXME: is this the right type?
              Arm64OpBarrier -> (Barrier . toEnum . fromIntegral) <$>
                 (peek bP :: IO CInt) -- FIXME: is this the right type?
              _ -> return Undefined
    poke p (CsArm64Op vI va ve (sh, shV) ext val) = do
        {#set cs_arm64_op->vector_index#} p (fromIntegral vI)
        {#set cs_arm64_op->vas#} p (fromIntegral $ fromEnum va)
        {#set cs_arm64_op->vess#} p (fromIntegral $ fromEnum ve)
        {#set cs_arm64_op->shift.type#} p (fromIntegral $ fromEnum sh)
        {#set cs_arm64_op->shift.value#} p (fromIntegral shV)
        {#set cs_arm64_op->ext#} p (fromIntegral $ fromEnum ext)
        let bP = plusPtr p -- FIXME: maybe alignment will bite us!
               ({#offsetof cs_arm64_op.type#} + {#sizeof arm64_op_type#})
            setType = {#set cs_arm64_op->type#} p
        case val of
          Reg r -> do
              poke bP (fromIntegral r :: CUInt)
              setType (fromIntegral $ fromEnum Arm64OpReg)
          Imm i -> do
              poke bP (fromIntegral i :: Int64)
              setType (fromIntegral $ fromEnum Arm64OpImm)
          CImm i -> do
              poke bP (fromIntegral i :: Int64)
              setType (fromIntegral $ fromEnum Arm64OpCimm)
          Fp f -> do
              poke bP (realToFrac f :: CDouble)
              setType (fromIntegral $ fromEnum Arm64OpFp)
          Mem m -> do
              poke bP m
              setType (fromIntegral $ fromEnum Arm64OpMem)
          Pstate p -> do -- FIXME: is this the right type?
              poke bP (fromIntegral $ fromEnum p :: CInt)
              setType (fromIntegral $ fromEnum Arm64OpRegMsr)
          Sys s -> do
              poke bP (fromIntegral s :: CUInt)
              setType (fromIntegral $ fromEnum Arm64OpSys)
          Prefetch p -> do -- FIXME: is this the right type?
              poke bP (fromIntegral $ fromEnum p :: CInt)
              setType (fromIntegral $ fromEnum Arm64OpPrefetch)
          Barrier b -> do -- FIXME: is this the right type?
              poke bP (fromIntegral $ fromEnum b :: CInt)
              setType (fromIntegral $ fromEnum Arm64OpBarrier)
          _ -> setType (fromIntegral $ fromEnum Arm64OpInvalid)

data CsArm64 = CsArm64
    { cc :: Arm64ConditionCode
    , updateFlags :: Bool
    , writeback :: Bool
    , operands :: [CsArm64Op]
    }

instance Storable CsArm64 where
    sizeOf _ = {#sizeof cs_arm64#}
    alignment _ = {#alignof cs_arm64#}
    peek p = CsArm64
        <$> (toEnum . fromIntegral <$> {#get cs_arm64->cc#} p)
        <*> ({#get cs_arm64->update_flags#} p)
        <*> ({#get cs_arm64->writeback#} p)
        <*> do num <- fromIntegral <$> {#get cs_arm64->op_count#} p
               let ptr = plusPtr p {#offsetof cs_arm64.operands#}
               peekArray num ptr
    poke p (CsArm64 cc uF w o) = do
        {#set cs_arm64->cc#} p (fromIntegral $ fromEnum cc)
        {#set cs_arm64->update_flags#} p uF
        {#set cs_arm64->writeback#} p w
        {#set cs_arm64->op_count#} p (fromIntegral $ length o)
        -- the proper way of writing array poking ;)
        pokeArray (plusPtr p {#offsetof cs_arm64->operands#}) o

{#enum arm64_reg as Arm64Reg {underscoreToCase} deriving (Show)#}
{#enum arm64_insn as Arm64Insn {underscoreToCase} deriving (Show)#}
{#enum arm64_insn_group as Arm64InsnGroup {underscoreToCase} deriving (Show)#}