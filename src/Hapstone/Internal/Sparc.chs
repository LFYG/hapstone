{-# LANGUAGE ForeignFunctionInterface #-}
module Hapstone.Internal.Sparc where

#include <capstone/sparc.h>

{#context lib = "capstone"#}

import Foreign
import Foreign.C.Types

{#enum sparc_cc as SparcCc {underscoreToCase} deriving (Show)#}
{#enum sparc_hint as SparcHint {underscoreToCase} deriving (Show)#}

{#enum sparc_op_type as SparcOpType {underscoreToCase} deriving (Show)#}

data SparcOpMemStruct = SparcOpMemStruct Word8 Word8 Int32

instance Storable SparcOpMemStruct where
    sizeOf _ = {#sizeof sparc_op_mem#}
    alignment _ = {#alignof sparc_op_mem#}
    peek p = SparcOpMemStruct
        <$> (fromIntegral <$> {#get sparc_op_mem->base#} p)
        <*> (fromIntegral <$> {#get sparc_op_mem->index#} p)
        <*> (fromIntegral <$> {#get sparc_op_mem->disp#} p)
    poke p (SparcOpMemStruct b i d) = do
        {#set sparc_op_mem->base#} p (fromIntegral b)
        {#set sparc_op_mem->index#} p (fromIntegral i)
        {#set sparc_op_mem->disp#} p (fromIntegral d)

data CsSparcOp
    = Reg Word32
    | Imm Int32
    | Mem SparcOpMemStruct
    | Undefined

instance Storable CsSparcOp where
    sizeOf _ = {#sizeof cs_sparc_op#}
    alignment _ = {#alignof cs_sparc_op#}
    peek p = do
        t <- fromIntegral <$> {#get cs_sparc_op->type#} p
        let bP = plusPtr p -- FIXME: maybe alignment will bite us!
               ({#offsetof cs_sparc_op.type#} + {#sizeof sparc_op_type#})
        case toEnum t of
          SparcOpReg -> (Reg . toEnum . fromIntegral) <$> (peek bP :: IO CInt)
          SparcOpImm -> Imm <$> peek bP
          SparcOpMem -> Mem <$> peek bP
          _ -> return Undefined
    poke p op = do
        let bP = plusPtr p -- FIXME: maybe alignment will bite us!
               ({#offsetof cs_sparc_op.type#} + {#sizeof sparc_op_type#})
            setType = {#set cs_sparc_op->type#} p . fromIntegral . fromEnum
        case op of
          Reg r -> do
              poke bP (fromIntegral $ fromEnum r :: CInt)
              setType SparcOpReg
          Imm i -> do
              poke bP i
              setType SparcOpImm
          Mem m -> do
              poke bP m
              setType SparcOpMem
          _ -> setType SparcOpInvalid

data CsSparc = CsSparc
    { cc :: SparcCc
    , hint :: SparcHint
    , operands :: [CsSparcOp]
    }

instance Storable CsSparc where
    sizeOf _ = {#sizeof cs_sparc#}
    alignment _ = {#alignof cs_sparc#}
    peek p = CsSparc
        <$> ((toEnum . fromIntegral) <$> {#get cs_sparc->cc#} p)
        <*> ((toEnum . fromIntegral) <$> {#get cs_sparc->hint#} p)
        <*> do num <- fromIntegral <$> {#get cs_sparc->op_count#} p
               let ptr = plusPtr p {#offsetof cs_sparc.operands#}
               peekArray num ptr
    poke p (CsSparc cc h o) = do
        {#set cs_sparc->cc#} p (fromIntegral $ fromEnum cc)
        {#set cs_sparc->hint#} p (fromIntegral $ fromEnum h)
        {#set cs_sparc->op_count#} p (fromIntegral $ length o)
        if length o > 4
           then error "operands overflew 4 elements"
           else pokeArray (plusPtr p {#offsetof cs_sparc->operands#}) o

{#enum sparc_reg as SparcReg {underscoreToCase} deriving (Show)#}
{#enum sparc_insn as SparcInsn {underscoreToCase} deriving (Show)#}
{#enum sparc_insn_group as SparcInsnGroup {underscoreToCase} deriving (Show)#}