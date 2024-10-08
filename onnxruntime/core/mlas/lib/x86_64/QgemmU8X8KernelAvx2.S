/*++

Copyright (c) Microsoft Corporation. All rights reserved.

Licensed under the MIT License.

Module Name:

    QgemmU8X8KernelAvx2.s

Abstract:

    This module implements the kernels for the quantized integer matrix/matrix
    multiply operation (QGEMM).

    This implementation uses AVX2 and AVX VNNI instructions.
    AVX-VNNI-INT8 support also included.

--*/

#include "asmmacro.h"
#include "AssembleAvxVnni.h"

        .intel_syntax noprefix

//
// Stack frame layout for the Int8 kernel.
//

        .equ    .LGemmInt8KernelFrame_type, -8
        .equ    .LGemmInt8KernelFrame_SavedR13, 0
        .equ    .LGemmInt8KernelFrame_SavedR12, 8
        .equ    .LGemmInt8KernelFrame_SavedRbx, 16
        .equ    .LGemmInt8KernelFrame_SavedRbp, 24
        .equ    .LGemmInt8KernelFrame_ReturnAddress, 32
        .equ    .LGemmInt8KernelFrame_ldc, 40
        .equ    .LGemmInt8KernelFrame_RowSumBuffer, 48
        .equ    .LGemmInt8KernelFrame_ColumnSumBuffer, 56
        .equ    .LGemmInt8KernelFrame_ZeroPointB, 64
        .equ    .LGemmInt8KernelFrame_ZeroMode, 72

/*++

Macro Description:

    This macro generates code to multiply and accumulator a single row of the
    output block.

Arguments:

    ColumnCount - Supplies the number of columns to produce.

    Vec1Reg - Supplies the high block accumulator register (when ColumnCount
        is 16).

    Vec2Reg - Supplies the low block accumulator register.

Implicit Arguments:

    ymm0 - Supplies the first vector loaded from matrix B.

    ymm1 - Supplies the second vector loaded from matrix B (when ColumnCount
        is 16).

    ymm2 - Supplies the broadcast value loaded from matrix A.

    ymm12 - Supplies a 256-bit with the broadcasted word value 0x0001.

--*/

        .macro MultiplyAccumulateRowU8S8Avx2 ColumnCount, Vec1Reg, Vec2Reg

        vpmaddubsw ymm3,ymm2,ymm0
        vpmaddwd ymm3,ymm3,ymm12
.if \ColumnCount\() == 16
        vpaddd  \Vec1Reg\(),\Vec1Reg\(),ymm3
        vpmaddubsw ymm2,ymm2,ymm1
        vpmaddwd ymm2,ymm2,ymm12
        vpaddd  \Vec2Reg\(),\Vec2Reg\(),ymm2
.else
        vpaddd  \Vec2Reg\(),\Vec2Reg\(),ymm3
.endif

        .endm

/*++

Macro Description:

    This macro generates code to multiply and accumulate each row of the output
    block.

Arguments:

    ColumnCount - Supplies the number of columns to produce.

    RowCount - Supplies the number of rows to produce.

    VectorOffset - Supplies the byte offset from matrix B to fetch elements.

    BroadcastOffset - Supplies the byte offset from matrix A to fetch elements.

Implicit Arguments:

    rdi - Supplies the address into the matrix A data.

    r8 - Supplies the address into the matrix A data plus 3 rows.

    rsi - Supplies the address into the matrix B data.

    rcx - Supplies the length in bytes of a row from matrix A.

    ymm4-ymm11 - Supplies the block accumulators.

    ymm12 - Supplies a 256-bit with the broadcasted word value 0x0001.

--*/

        .macro ComputeBlockAvx2 ColumnCount, RowCount, VectorOffset, BroadcastOffset, ASigned, BSigned

.if \RowCount\() == 1
        vpbroadcastd ymm2,DWORD PTR [rdi+\BroadcastOffset\()]
        vpmaddubsw ymm3,ymm2,YMMWORD PTR [rsi+\VectorOffset\()]
        vpmaddwd ymm3,ymm3,ymm12
.if \ColumnCount\() == 16
        vpaddd  ymm4,ymm4,ymm3
        vpmaddubsw ymm2,ymm2,YMMWORD PTR [rsi+\VectorOffset\()+32]
        vpmaddwd ymm2,ymm2,ymm12
        vpaddd  ymm5,ymm5,ymm2
.else
        vpaddd  ymm5,ymm5,ymm3
.endif
.else
        vmovdqu ymm0,YMMWORD PTR [rsi+\VectorOffset\()]
        EmitIfCountGE \ColumnCount\(), 16, "vmovdqu ymm1,YMMWORD PTR [rsi+\VectorOffset\()+32]"
        EmitIfCountGE \RowCount\(), 1, "vpbroadcastd ymm2,DWORD PTR [rdi+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 1, "MultiplyAccumulateRowU8S8Avx2 \ColumnCount\(), ymm4, ymm5"
        EmitIfCountGE \RowCount\(), 2, "vpbroadcastd ymm2,DWORD PTR [rdi+rcx+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 2, "MultiplyAccumulateRowU8S8Avx2 \ColumnCount\(), ymm6, ymm7"
        EmitIfCountGE \RowCount\(), 3, "vpbroadcastd ymm2,DWORD PTR [rdi+rcx*2+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 3, "MultiplyAccumulateRowU8S8Avx2 \ColumnCount\(), ymm8, ymm9"
        EmitIfCountGE \RowCount\(), 4, "vpbroadcastd ymm2,DWORD PTR [r8+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 4, "MultiplyAccumulateRowU8S8Avx2 \ColumnCount\(), ymm10, ymm11"
.endif

        .endm

/*++
Macro Description:

    This macro generates code to multiply and accumulator a single row of the
    output block.

Arguments:

    ColumnCount - Supplies the number of columns to produce.

    Vec1Reg - Supplies the high block accumulator register (when ColumnCount
        is 16).

    Vec2Reg - Supplies the low block accumulator register.

Implicit Arguments:

    ymm0 - Supplies the first vector loaded from matrix B.

    ymm1 - Supplies the second vector loaded from matrix B (when ColumnCount
        is 16).

    ymm2 - Supplies the broadcast value loaded from matrix A.

--*/

        .macro MultiplyAccumulateRowAvxVnni ColumnCount, Vec1Reg, Vec2Reg, ASigned, BSigned

.if \ASigned\() == 1
    .if \BSigned\() == 1
        .if \ColumnCount\() == 16
            VpdpbssdYmmYmmYmm \Vec1Reg\(),ymm2,ymm0
            VpdpbssdYmmYmmYmm \Vec2Reg\(),ymm2,ymm1
        .else
            VpdpbssdYmmYmmYmm \Vec2Reg\(),ymm2,ymm0
        .endif
    .else
        .if \ColumnCount\() == 16
            VpdpbsudYmmYmmYmm \Vec1Reg\(),ymm2,ymm0
            VpdpbsudYmmYmmYmm \Vec2Reg\(),ymm2,ymm1
        .else
            VpdpbsudYmmYmmYmm \Vec2Reg\(),ymm2,ymm0
        .endif
    .endif
.else
    .if \BSigned\() == 1
        .if \ColumnCount\() == 16
            VpdpbusdYmmYmmYmm \Vec1Reg\(),ymm2,ymm0
            VpdpbusdYmmYmmYmm \Vec2Reg\(),ymm2,ymm1
        .else
            VpdpbusdYmmYmmYmm \Vec2Reg\(),ymm2,ymm0
        .endif
    .else
        .if \ColumnCount\() == 16
            VpdpbuudYmmYmmYmm \Vec1Reg\(),ymm2,ymm0
            VpdpbuudYmmYmmYmm \Vec2Reg\(),ymm2,ymm1
        .else
            VpdpbuudYmmYmmYmm \Vec2Reg\(),ymm2,ymm0
        .endif
    .endif
.endif

        .endm

/*++

Macro Description:

    This macro generates code to multiply and accumulate each row of the output
    block.

Arguments:

    ColumnCount - Supplies the number of columns to produce.

    RowCount - Supplies the number of rows to produce.

    VectorOffset - Supplies the byte offset from matrix B to fetch elements.

    BroadcastOffset - Supplies the byte offset from matrix A to fetch elements.

Implicit Arguments:

    rdi - Supplies the address into the matrix A data.

    r8 - Supplies the address into the matrix A data plus 3 rows.

    rsi - Supplies the address into the matrix B data.

    rcx - Supplies the length in bytes of a row from matrix A.

    ymm4-ymm15 - Supplies the block accumulators.

--*/

        .macro ComputeBlockAvxVnni ColumnCount, RowCount, VectorOffset, BroadcastOffset, ASigned, BSigned

        vmovdqu ymm0,YMMWORD PTR [rsi+\VectorOffset\()]
        EmitIfCountGE \ColumnCount\(), 16, "vmovdqu ymm1,YMMWORD PTR [rsi+\VectorOffset\()+32]"
        EmitIfCountGE \RowCount\(), 1, "vpbroadcastd ymm2,DWORD PTR [rdi+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 1, "MultiplyAccumulateRowAvxVnni \ColumnCount\(), ymm4, ymm5, \ASigned\(), \BSigned\()"
        EmitIfCountGE \RowCount\(), 2, "vpbroadcastd ymm2,DWORD PTR [rdi+rcx+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 2, "MultiplyAccumulateRowAvxVnni \ColumnCount\(), ymm6, ymm7, \ASigned\(), \BSigned\()"
        EmitIfCountGE \RowCount\(), 3, "vpbroadcastd ymm2,DWORD PTR [rdi+rcx*2+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 3, "MultiplyAccumulateRowAvxVnni \ColumnCount\(), ymm8, ymm9, \ASigned\(), \BSigned\()"
        EmitIfCountGE \RowCount\(), 4, "vpbroadcastd ymm2,DWORD PTR [r8+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 4, "MultiplyAccumulateRowAvxVnni \ColumnCount\(), ymm10, ymm11, \ASigned\(), \BSigned\()"
        EmitIfCountGE \RowCount\(), 5, "vpbroadcastd ymm2,DWORD PTR [r8+rcx+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 5, "MultiplyAccumulateRowAvxVnni \ColumnCount\(), ymm12, ymm13, \ASigned\(), \BSigned\()"
        EmitIfCountGE \RowCount\(), 6, "vpbroadcastd ymm2,DWORD PTR [r8+rcx*2+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 6, "MultiplyAccumulateRowAvxVnni \ColumnCount\(), ymm14, ymm15, \ASigned\(), \BSigned\()"

        .endm

/*++

Macro Description:

    This macro generates code to execute the block compute macro multiple times
    and advancing the matrix A and matrix B data pointers.

Arguments:

    Isa - Supplies the instruction set architecture string.

    ColumnCount - Supplies the number of columns to produce.

    RowCount - Supplies the number of rows to produce.

Implicit Arguments:

    r8 - Supplies the address into the matrix A data plus 3 rows.

    rdi - Supplies the address into the matrix A data.

    rsi - Supplies the address into the matrix B data.

    rcx - Supplies the length in bytes of a row from matrix A.

    ymm4-ymm11 - Supplies the block accumulators.

--*/

        .macro ComputeBlockLoop Isa, ColumnCount, RowCount, ASigned, BSigned

        mov     rbp,rcx                     # reload row length remaining

.if (\ColumnCount\() == 16) && (\RowCount\() == 1)
        sub     rbp,4*4
        jb      .LProcessRemainingBlocks\@

.LComputeBlockBy4Loop\@:
        ComputeBlock\Isa\() \ColumnCount\(), \RowCount\(), 0*64, 0, \ASigned\(), \BSigned\()
        ComputeBlock\Isa\() \ColumnCount\(), \RowCount\(), 1*64, 4, \ASigned\(), \BSigned\()
        ComputeBlock\Isa\() \ColumnCount\(), \RowCount\(), 2*64, 8, \ASigned\(), \BSigned\()
        ComputeBlock\Isa\() \ColumnCount\(), \RowCount\(), 3*64, 12, \ASigned\(), \BSigned\()
        add     rdi,4*4                     # advance matrix A by 4 quads
        add     rsi,4*64                    # advance matrix B
        sub     rbp,4*4
        jae     .LComputeBlockBy4Loop\@

.LProcessRemainingBlocks\@:
        add     rbp,4*4                     # correct for over-subtract above
        jz      .LComputeBlockLoopExit\@
.endif

.LComputeBlockBy1Loop\@:
        ComputeBlock\Isa\() \ColumnCount\(), \RowCount\(), 0, 0, \ASigned\(), \BSigned\()
        add     rdi,4                       # advance matrix A by 1 quad
.if \RowCount\() > 3
        add     r8,4                        # advance matrix A plus 3 rows by 1 quad
.endif
        add     rsi,64                      # advance matrix B
        sub     rbp,4
        jnz     .LComputeBlockBy1Loop\@

.LComputeBlockLoopExit\@:

        .endm

/*++

Macro Description:

    This macro generates code to multiply and accumulator a single row of the
    output block.

Arguments:

    ColumnCount - Supplies the number of columns to produce.

    Vec1Reg - Supplies the high block accumulator register (when ColumnCount
        is 16).

    Vec2Reg - Supplies the low block accumulator register.

Implicit Arguments:

    ymm0 - Supplies the first vector loaded from matrix B.

    ymm1 - Supplies the second vector loaded from matrix B (when ColumnCount
        is 16).

    ymm2 - Supplies the broadcast value loaded from matrix A.

--*/

        .macro MultiplyAccumulateRowU8U8Avx2 ColumnCount, Vec1Reg, Vec2Reg

        vpmaddwd ymm3,ymm2,ymm0
.if \ColumnCount\() == 16
        vpaddd  \Vec1Reg\(),\Vec1Reg\(),ymm3
        vpmaddwd ymm2,ymm2,ymm1
        vpaddd  \Vec2Reg\(),\Vec2Reg\(),ymm2
.else
        vpaddd  \Vec2Reg\(),\Vec2Reg\(),ymm3
.endif

        .endm

/*++

Macro Description:

    This macro generates code to multiply and accumulate each row of the output
    block.

Arguments:

    ColumnCount - Supplies the number of columns to produce.

    RowCount - Supplies the number of rows to produce.

    VectorOffset - Supplies the byte offset from matrix B to fetch elements.

    BroadcastOffset - Supplies the byte offset from matrix A to fetch elements.

Implicit Arguments:

    rdi - Supplies the address into the matrix A data.

    r8 - Supplies the address into the matrix A data plus 3 rows.

    rsi - Supplies the address into the matrix B data.

    rcx - Supplies the length in bytes of a row from matrix A.

    ymm4-ymm15 - Supplies the block accumulators.

--*/

        .macro ComputeBlockU8U8Avx2 ColumnCount, RowCount, VectorOffset, BroadcastOffset

        vpmovzxbw ymm0,XMMWORD PTR [rsi+\VectorOffset\()]
        EmitIfCountGE \ColumnCount\(), 16, "vpmovzxbw ymm1,XMMWORD PTR [rsi+\VectorOffset\()+16]"
        EmitIfCountGE \RowCount\(), 1, "vpbroadcastd ymm2,DWORD PTR [rdi+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 1, "MultiplyAccumulateRowU8U8Avx2 \ColumnCount\(), ymm4, ymm5"
        EmitIfCountGE \RowCount\(), 2, "vpbroadcastd ymm2,DWORD PTR [rdi+rcx+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 2, "MultiplyAccumulateRowU8U8Avx2 \ColumnCount\(), ymm6, ymm7"
        EmitIfCountGE \RowCount\(), 3, "vpbroadcastd ymm2,DWORD PTR [rdi+rcx*2+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 3, "MultiplyAccumulateRowU8U8Avx2 \ColumnCount\(), ymm8, ymm9"
        EmitIfCountGE \RowCount\(), 4, "vpbroadcastd ymm2,DWORD PTR [r8+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 4, "MultiplyAccumulateRowU8U8Avx2 \ColumnCount\(), ymm10, ymm11"
        EmitIfCountGE \RowCount\(), 5, "vpbroadcastd ymm2,DWORD PTR [r8+rcx+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 5, "MultiplyAccumulateRowU8U8Avx2 \ColumnCount\(), ymm12, ymm13"
        EmitIfCountGE \RowCount\(), 6, "vpbroadcastd ymm2,DWORD PTR [r8+rcx*2+\BroadcastOffset\()]"
        EmitIfCountGE \RowCount\(), 6, "MultiplyAccumulateRowU8U8Avx2 \ColumnCount\(), ymm14, ymm15"

        .endm

/*++

Macro Description:

    This macro generates code to execute the block compute macro multiple times
    and advancing the matrix A and matrix B data pointers.

Arguments:

    Isa - Supplies the instruction set architecture string.

    ColumnCount - Supplies the number of columns to produce.

    RowCount - Supplies the number of rows to produce.

Implicit Arguments:

    rdi - Supplies the address into the matrix A data.

    r8 - Supplies the address into the matrix A data plus 3 rows.

    rsi - Supplies the address into the matrix B data.

    rcx - Supplies the length in bytes of a row from matrix A.

    ymm4-ymm15 - Supplies the block accumulators.

--*/

        .macro ComputeBlockLoopU8U8 Isa, ColumnCount, RowCount

        mov     rbp,rcx                     # reload row length remaining

.if (\ColumnCount\() == 16) && ((\RowCount\() & 1) == 0)
        sub     rbp,2*4
        jb      .LProcessRemainingBlocks\@

.LComputeBlockBy2Loop\@:
        ComputeBlockU8U8\Isa\() \ColumnCount\(), \RowCount\(), 0, 0
        ComputeBlockU8U8\Isa\() \ColumnCount\(), \RowCount\(), 32, 4
        add     rdi,2*4                     # advance matrix A by 2 pairs
.if \RowCount\() > 3
        add     r8,2*4                      # advance matrix A plus 3 rows by 2 pairs
.endif
        add     rsi,2*32                    # advance matrix B
        sub     rbp,2*4
        jae     .LComputeBlockBy2Loop\@

.LProcessRemainingBlocks\@:
        add     rbp,2*4                     # correct for over-subtract above
        jz      .LComputeBlockLoopExit\@
        ComputeBlockU8U8\Isa\() \ColumnCount\(), \RowCount\(), 0, 0
        add     rsi,32                      # advance matrix B
.else
.LComputeBlockBy1Loop\@:
        ComputeBlockU8U8\Isa\() \ColumnCount\(), \RowCount\(), 0, 0
        add     rdi,4                       # advance matrix A by 1 pair
.if \RowCount\() > 3
        add     r8,4                        # advance matrix A plus 3 rows by 1 pair
.endif
        add     rsi,32                      # advance matrix B
        sub     rbp,4
        jnz     .LComputeBlockBy1Loop\@
.endif

.LComputeBlockLoopExit\@:

        .endm

/*++

Macro Description:

    This macro generates code to produce an output block for a set of columns
    and rows.

Arguments:

    ColumnCount - Supplies the number of columns to produce.

    RowCount - Supplies the number of rows to produce.

Implicit Arguments:

    rax - Supplies the length in bytes of a row from matrix C.

    rdi - Supplies the address into the matrix A data.

    rsi - Supplies the address into the matrix B data.

    rcx - Supplies the length in bytes of a row from matrix A.

    r11 - Supplies the address of the row sum buffer.

    r12 - Supplies the address of the column sum buffer.

    ymm4-ymm15 - Supplies the block accumulators.

--*/

        .macro ProduceOutputBlock ColumnCount, RowCount, ASigned, BSigned

//
// Initialize the accumulators with the row and column sums.
//

        EmitIfCountGE \RowCount\(), 1, "vpbroadcastd ymm5,DWORD PTR [r11]"
        EmitIfCountGE \RowCount\(), 2, "vpbroadcastd ymm7,DWORD PTR [r11+4]"
        EmitIfCountGE \RowCount\(), 3, "vpbroadcastd ymm9,DWORD PTR [r11+8]"
        EmitIfCountGE \RowCount\(), 4, "vpbroadcastd ymm11,DWORD PTR [r11+12]"
        EmitIfCountGE \RowCount\(), 5, "vpbroadcastd ymm13,DWORD PTR [r11+16]"
        EmitIfCountGE \RowCount\(), 6, "vpbroadcastd ymm15,DWORD PTR [r11+20]"
.if \ColumnCount\() == 16
        vmovdqu ymm0,YMMWORD PTR [r12]
        vmovdqu ymm1,YMMWORD PTR [r12+32]
        add     r12,16*4                    # advance ColumnSumBuffer by 16 columns
.else
        vmovdqu ymm1,YMMWORD PTR [r12]
.endif
        test    r13,r13                     # per column zero points?
        jz      .LSkipScaleByZeroPointB\@
.if \ColumnCount\() == 16
        vmovdqu ymm2,YMMWORD PTR [r13]
        vmovdqu ymm3,YMMWORD PTR [r13+32]
        add     r13,16*4                    # advance ZeroPointB by 16 columns
.else
        vmovdqu ymm3,YMMWORD PTR [r13]
.endif
        EmitIfCount2GE \RowCount\(), 1, \ColumnCount\(), 16, "vpmulld ymm4,ymm5,ymm2"
        EmitIfCountGE \RowCount\(), 1, "vpmulld ymm5,ymm5,ymm3"
        EmitIfCount2GE \RowCount\(), 1, \ColumnCount\(), 16, "vpaddd ymm4,ymm0,ymm4"
        EmitIfCountGE \RowCount\(), 1, "vpaddd ymm5,ymm1,ymm5"
        EmitIfCount2GE \RowCount\(), 2, \ColumnCount\(), 16, "vpmulld ymm6,ymm7,ymm2"
        EmitIfCountGE \RowCount\(), 2, "vpmulld ymm7,ymm7,ymm3"
        EmitIfCount2GE \RowCount\(), 2, \ColumnCount\(), 16, "vpaddd ymm6,ymm0,ymm6"
        EmitIfCountGE \RowCount\(), 2, "vpaddd ymm7,ymm1,ymm7"
        EmitIfCount2GE \RowCount\(), 3, \ColumnCount\(), 16, "vpmulld ymm8,ymm9,ymm2"
        EmitIfCountGE \RowCount\(), 3, "vpmulld ymm9,ymm9,ymm3"
        EmitIfCount2GE \RowCount\(), 3, \ColumnCount\(), 16, "vpaddd ymm8,ymm0,ymm8"
        EmitIfCountGE \RowCount\(), 3, "vpaddd ymm9,ymm1,ymm9"
        EmitIfCount2GE \RowCount\(), 4, \ColumnCount\(), 16, "vpmulld ymm10,ymm11,ymm2"
        EmitIfCountGE \RowCount\(), 4, "vpmulld ymm11,ymm11,ymm3"
        EmitIfCount2GE \RowCount\(), 4, \ColumnCount\(), 16, "vpaddd ymm10,ymm0,ymm10"
        EmitIfCountGE \RowCount\(), 4, "vpaddd ymm11,ymm1,ymm11"
        EmitIfCount2GE \RowCount\(), 5, \ColumnCount\(), 16, "vpmulld ymm12,ymm13,ymm2"
        EmitIfCountGE \RowCount\(), 5, "vpmulld ymm13,ymm13,ymm3"
        EmitIfCount2GE \RowCount\(), 5, \ColumnCount\(), 16, "vpaddd ymm12,ymm0,ymm12"
        EmitIfCountGE \RowCount\(), 5, "vpaddd ymm13,ymm1,ymm13"
        EmitIfCount2GE \RowCount\(), 6, \ColumnCount\(), 16, "vpmulld ymm14,ymm15,ymm2"
        EmitIfCountGE \RowCount\(), 6, "vpmulld ymm15,ymm15,ymm3"
        EmitIfCount2GE \RowCount\(), 6, \ColumnCount\(), 16, "vpaddd ymm14,ymm0,ymm14"
        EmitIfCountGE \RowCount\(), 6, "vpaddd ymm15,ymm1,ymm15"
        jmp     .LAccumulatorsInitialized\@

.LSkipScaleByZeroPointB\@:
        EmitIfCount2GE \RowCount\(), 1, \ColumnCount\(), 16, "vpaddd ymm4,ymm5,ymm0"
        EmitIfCountGE \RowCount\(), 1, "vpaddd ymm5,ymm5,ymm1"
        EmitIfCount2GE \RowCount\(), 2, \ColumnCount\(), 16, "vpaddd ymm6,ymm7,ymm0"
        EmitIfCountGE \RowCount\(), 2, "vpaddd ymm7,ymm7,ymm1"
        EmitIfCount2GE \RowCount\(), 3, \ColumnCount\(), 16, "vpaddd ymm8,ymm9,ymm0"
        EmitIfCountGE \RowCount\(), 3, "vpaddd ymm9,ymm9,ymm1"
        EmitIfCount2GE \RowCount\(), 4, \ColumnCount\(), 16, "vpaddd ymm10,ymm11,ymm0"
        EmitIfCountGE \RowCount\(), 4, "vpaddd ymm11,ymm11,ymm1"
        EmitIfCount2GE \RowCount\(), 5, \ColumnCount\(), 16, "vpaddd ymm12,ymm13,ymm0"
        EmitIfCountGE \RowCount\(), 5, "vpaddd ymm13,ymm13,ymm1"
        EmitIfCount2GE \RowCount\(), 6, \ColumnCount\(), 16, "vpaddd ymm14,ymm15,ymm0"
        EmitIfCountGE \RowCount\(), 6, "vpaddd ymm15,ymm15,ymm1"

.LAccumulatorsInitialized\@:

//
// Iterate over the length of a matrix A row to produce the output accumulators.
//

.if \RowCount\() > 3
        lea     r8,[rcx*2+rcx]
        add     r8,rdi                      # compute matrix A plus 3 rows
.endif
        cmp     DWORD PTR .LGemmInt8KernelFrame_type[rsp],0
        jg      .LProduceWithU8U8Avx2\@
.if \RowCount\() <= 4
        jl      .LProduceWithInt8AvxVnni\@
        ComputeBlockLoop Avx2, \ColumnCount\(), \RowCount\(), \ASigned\(), \BSigned\()
        jmp     .LExitProduceOutputBlock\@
.endif

.LProduceWithInt8AvxVnni\@:
        ComputeBlockLoop AvxVnni, \ColumnCount\(), \RowCount\(), \ASigned\(), \BSigned\()
        jmp     .LExitProduceOutputBlock\@

.LProduceWithU8U8Avx2\@:
        ComputeBlockLoopU8U8 Avx2, \ColumnCount\(), \RowCount\()

.LExitProduceOutputBlock\@:
.if \RowCount\() > 3
        lea     r8,[rax*2+rax]
        add     r8,rdx                      # compute matrix C plus 3 rows
.endif

        .endm

/*++

Macro Description:

    This macro generates code to compute matrix multiplication for a fixed set
    of rows.

Arguments:

    RowCount - Supplies the number of rows to process.

Implicit Arguments:

    rax - Supplies the length in bytes of a row from matrix C.

    rdi - Supplies the address of matrix A.

    rsi - Supplies the address of matrix B.

    rdx - Supplies the address of matrix C.

    rbx - Supplies the address of matrix A.

    r9 - Supplies the number of columns from matrix B and matrix C to iterate
        over.

    rcx - Supplies the length in bytes of a row from matrix A.

    r10b - Supplies the zero mode flag.

    r11 - Supplies the address of the row sum buffer.

    r12 - Supplies the address of the column sum buffer.

--*/

        .macro ProcessCountM RowCount, ASigned, BSigned

        cmp     r9,8
        jbe     .LProcessRemainingCountN\@

.LProcessNextColumnLoop16xN\@:
        ProduceOutputBlock 16, \RowCount\(), \ASigned\(), \BSigned\()
        sub     r9,16
        jb      .LOutputMasked16xNBlock\@
        test    r10b,r10b                   # ZeroMode?
        jnz     .LSkipAccumulateOutput16xNBlock\@
        EmitIfCountGE \RowCount\(), 1, "vpaddd ymm4,ymm4,YMMWORD PTR [rdx]"
        EmitIfCountGE \RowCount\(), 1, "vpaddd ymm5,ymm5,YMMWORD PTR [rdx+32]"
        EmitIfCountGE \RowCount\(), 2, "vpaddd ymm6,ymm6,YMMWORD PTR [rdx+rax]"
        EmitIfCountGE \RowCount\(), 2, "vpaddd ymm7,ymm7,YMMWORD PTR [rdx+rax+32]"
        EmitIfCountGE \RowCount\(), 3, "vpaddd ymm8,ymm8,YMMWORD PTR [rdx+rax*2]"
        EmitIfCountGE \RowCount\(), 3, "vpaddd ymm9,ymm9,YMMWORD PTR [rdx+rax*2+32]"
        EmitIfCountGE \RowCount\(), 4, "vpaddd ymm10,ymm10,YMMWORD PTR [r8]"
        EmitIfCountGE \RowCount\(), 4, "vpaddd ymm11,ymm11,YMMWORD PTR [r8+32]"
        EmitIfCountGE \RowCount\(), 5, "vpaddd ymm12,ymm12,YMMWORD PTR [r8+rax]"
        EmitIfCountGE \RowCount\(), 5, "vpaddd ymm13,ymm13,YMMWORD PTR [r8+rax+32]"
        EmitIfCountGE \RowCount\(), 6, "vpaddd ymm14,ymm14,YMMWORD PTR [r8+rax*2]"
        EmitIfCountGE \RowCount\(), 6, "vpaddd ymm15,ymm15,YMMWORD PTR [r8+rax*2+32]"

.LSkipAccumulateOutput16xNBlock\@:
        EmitIfCountGE \RowCount\(), 1, "vmovdqu YMMWORD PTR [rdx],ymm4"
        EmitIfCountGE \RowCount\(), 1, "vmovdqu YMMWORD PTR [rdx+32],ymm5"
        EmitIfCountGE \RowCount\(), 2, "vmovdqu YMMWORD PTR [rdx+rax],ymm6"
        EmitIfCountGE \RowCount\(), 2, "vmovdqu YMMWORD PTR [rdx+rax+32],ymm7"
        EmitIfCountGE \RowCount\(), 3, "vmovdqu YMMWORD PTR [rdx+rax*2],ymm8"
        EmitIfCountGE \RowCount\(), 3, "vmovdqu YMMWORD PTR [rdx+rax*2+32],ymm9"
        EmitIfCountGE \RowCount\(), 4, "vmovdqu YMMWORD PTR [r8],ymm10"
        EmitIfCountGE \RowCount\(), 4, "vmovdqu YMMWORD PTR [r8+32],ymm11"
        EmitIfCountGE \RowCount\(), 5, "vmovdqu YMMWORD PTR [r8+rax],ymm12"
        EmitIfCountGE \RowCount\(), 5, "vmovdqu YMMWORD PTR [r8+rax+32],ymm13"
        EmitIfCountGE \RowCount\(), 6, "vmovdqu YMMWORD PTR [r8+rax*2],ymm14"
        EmitIfCountGE \RowCount\(), 6, "vmovdqu YMMWORD PTR [r8+rax*2+32],ymm15"
        add     rdx,16*4                    # advance matrix C by 16 columns
        mov     rdi,rbx                     # reload matrix A
        cmp     r9,8
        ja      .LProcessNextColumnLoop16xN\@
        test    r9,r9
        jnz     .LProcessRemainingCountN\@

.LExitProcessCountM\@:
        mov     eax,\RowCount\()
        jmp     .LExitKernel

.LProcessRemainingCountN\@:
        ProduceOutputBlock 8, \RowCount\(), \ASigned\(), \BSigned\()
        cmp     r9,8
        jb      .LOutputMasked8xNBlock\@
        test    r10b,r10b                   # ZeroMode?
        jnz     .LSkipAccumulateOutput8xNBlock\@
        EmitIfCountGE \RowCount\(), 1, "vpaddd ymm5,ymm5,YMMWORD PTR [rdx]"
        EmitIfCountGE \RowCount\(), 2, "vpaddd ymm7,ymm7,YMMWORD PTR [rdx+rax]"
        EmitIfCountGE \RowCount\(), 3, "vpaddd ymm9,ymm9,YMMWORD PTR [rdx+rax*2]"
        EmitIfCountGE \RowCount\(), 4, "vpaddd ymm11,ymm11,YMMWORD PTR [r8]"
        EmitIfCountGE \RowCount\(), 5, "vpaddd ymm13,ymm13,YMMWORD PTR [r8+rax]"
        EmitIfCountGE \RowCount\(), 6, "vpaddd ymm15,ymm15,YMMWORD PTR [r8+rax*2]"

.LSkipAccumulateOutput8xNBlock\@:
        EmitIfCountGE \RowCount\(), 1, "vmovdqu YMMWORD PTR [rdx],ymm5"
        EmitIfCountGE \RowCount\(), 2, "vmovdqu YMMWORD PTR [rdx+rax],ymm7"
        EmitIfCountGE \RowCount\(), 3, "vmovdqu YMMWORD PTR [rdx+rax*2],ymm9"
        EmitIfCountGE \RowCount\(), 4, "vmovdqu YMMWORD PTR [r8],ymm11"
        EmitIfCountGE \RowCount\(), 5, "vmovdqu YMMWORD PTR [r8+rax],ymm13"
        EmitIfCountGE \RowCount\(), 6, "vmovdqu YMMWORD PTR [r8+rax*2],ymm15"
        jmp     .LExitProcessCountM\@

.LOutputMasked16xNBlock\@:
        test    r10b,r10b                   # ZeroMode?
        jnz     .LSkipAccumulateOutputMasked16xNBlock\@
        EmitIfCountGE \RowCount\(), 1, "vpaddd ymm4,ymm4,YMMWORD PTR [rdx]"
        EmitIfCountGE \RowCount\(), 2, "vpaddd ymm6,ymm6,YMMWORD PTR [rdx+rax]"
        EmitIfCountGE \RowCount\(), 3, "vpaddd ymm8,ymm8,YMMWORD PTR [rdx+rax*2]"
        EmitIfCountGE \RowCount\(), 4, "vpaddd ymm10,ymm10,YMMWORD PTR [r8]"
        EmitIfCountGE \RowCount\(), 5, "vpaddd ymm12,ymm12,YMMWORD PTR [r8+rax]"
        EmitIfCountGE \RowCount\(), 6, "vpaddd ymm14,ymm14,YMMWORD PTR [r8+rax*2]"

.LSkipAccumulateOutputMasked16xNBlock\@:
        EmitIfCountGE \RowCount\(), 1, "vmovdqu YMMWORD PTR [rdx],ymm4"
        EmitIfCountGE \RowCount\(), 2, "vmovdqu YMMWORD PTR [rdx+rax],ymm6"
        EmitIfCountGE \RowCount\(), 3, "vmovdqu YMMWORD PTR [rdx+rax*2],ymm8"
        EmitIfCountGE \RowCount\(), 4, "vmovdqu YMMWORD PTR [r8],ymm10"
        EmitIfCountGE \RowCount\(), 5, "vmovdqu YMMWORD PTR [r8+rax],ymm12"
        EmitIfCountGE \RowCount\(), 6, "vmovdqu YMMWORD PTR [r8+rax*2],ymm14"
        add     rdx,8*4                     # advance matrix C by 8 columns
.if \RowCount\() > 3
        add     r8,8*4                      # advance matrix C plus 3 rows by 8 columns
.endif
        add     r9,8                        # correct for over-subtract above

.LOutputMasked8xNBlock\@:
        neg     r9
        lea     rdi,C_UNDERSCORE(MlasMaskMoveTableAvx)[rip+8*4]
        vmovdqu ymm0,YMMWORD PTR [rdi+r9*4]
        test    r10b,r10b                   # ZeroMode?
        jnz     .LSkipAccumulateOutputMasked8xNBlock\@
        EmitIfCountGE \RowCount\(), 1, "vpmaskmovd ymm4,ymm0,YMMWORD PTR [rdx]"
        EmitIfCountGE \RowCount\(), 2, "vpmaskmovd ymm6,ymm0,YMMWORD PTR [rdx+rax]"
        EmitIfCountGE \RowCount\(), 3, "vpmaskmovd ymm8,ymm0,YMMWORD PTR [rdx+rax*2]"
        EmitIfCountGE \RowCount\(), 4, "vpmaskmovd ymm10,ymm0,YMMWORD PTR [r8]"
        EmitIfCountGE \RowCount\(), 5, "vpmaskmovd ymm12,ymm0,YMMWORD PTR [r8+rax]"
        EmitIfCountGE \RowCount\(), 6, "vpmaskmovd ymm14,ymm0,YMMWORD PTR [r8+rax*2]"
        EmitIfCountGE \RowCount\(), 1, "vpaddd ymm5,ymm5,ymm4"
        EmitIfCountGE \RowCount\(), 2, "vpaddd ymm7,ymm7,ymm6"
        EmitIfCountGE \RowCount\(), 3, "vpaddd ymm9,ymm9,ymm8"
        EmitIfCountGE \RowCount\(), 4, "vpaddd ymm11,ymm11,ymm10"
        EmitIfCountGE \RowCount\(), 5, "vpaddd ymm13,ymm13,ymm12"
        EmitIfCountGE \RowCount\(), 6, "vpaddd ymm15,ymm15,ymm14"

.LSkipAccumulateOutputMasked8xNBlock\@:
        EmitIfCountGE \RowCount\(), 1, "vpmaskmovd YMMWORD PTR [rdx],ymm0,ymm5"
        EmitIfCountGE \RowCount\(), 2, "vpmaskmovd YMMWORD PTR [rdx+rax],ymm0,ymm7"
        EmitIfCountGE \RowCount\(), 3, "vpmaskmovd YMMWORD PTR [rdx+rax*2],ymm0,ymm9"
        EmitIfCountGE \RowCount\(), 4, "vpmaskmovd YMMWORD PTR [r8],ymm0,ymm11"
        EmitIfCountGE \RowCount\(), 5, "vpmaskmovd YMMWORD PTR [r8+rax],ymm0,ymm13"
        EmitIfCountGE \RowCount\(), 6, "vpmaskmovd YMMWORD PTR [r8+rax*2],ymm0,ymm15"
        jmp     .LExitProcessCountM\@

        .endm

/*++

Routine Description:

    This routine is an inner kernel to compute matrix multiplication for a
    set of rows.

Arguments:

    A (rdi) - Supplies the address of matrix A. The matrix data has been packed
        using MlasGemmCopyPackAAvx2.

    B (rsi) - Supplies the address of matrix B. The matrix data has been packed
        using MlasGemmCopyPackBAvx2.

    C (rdx) - Supplies the address of matrix C.

    PackedCountK (rcx) - Supplies the number of packed columns from matrix A
        and the number of packed rows from matrix B to iterate over.

    CountM (r8) - Supplies the maximum number of rows that can be processed for
        matrix A and matrix C. The actual number of rows handled for this
        invocation depends on the kernel implementation.

    CountN (r9) - Supplies the number of columns from matrix B and matrix C to
        iterate over.

    ldc - Supplies the first dimension of matrix C.

    RowSumBuffer - Supplies the sum of each row from matrix A. These values have
        been pre-scaled by the zero point offset of matrix B if the offset is
        per-tensor (ZeroPointB is nullptr). Otherwise, these values must be
        scaled by the per-column zero point offsets of matrix B. These values are
        accumulated into every row of matrix C.

    ColumnSumBuffer - Supplies the sum of each column from matrix B multiplied
        by the zero point offset of matrix A. These values are accumulated into
        every column of matrix C.

    ZeroPointB - Optionally supplies the per-column zero point offsets of matrix
        B, else nullptr if the matrix B is using per-tensor quantization.

    ZeroMode - Supplies true if the output matrix must be zero initialized,
        else false if the output matrix is accumulated into.

Return Value:

    Returns the number of rows handled.

--*/

.macro MlasGemmInt8KernelAvx2 ASigned, BSigned

        push    rbp
        push    rbx
        push    r12
        push    r13

        mov     DWORD PTR .LGemmInt8KernelFrame_type[rsp],eax
        mov     rbx,rdi
        mov     rax,.LGemmInt8KernelFrame_ldc[rsp]
        shl     rax,2                       # convert ldc to bytes
        shl     rcx,2                       # convert to row length
        movzx   r10,BYTE PTR .LGemmInt8KernelFrame_ZeroMode[rsp]
        mov     r11,.LGemmInt8KernelFrame_RowSumBuffer[rsp]
        mov     r12,.LGemmInt8KernelFrame_ColumnSumBuffer[rsp]
        mov     r13,.LGemmInt8KernelFrame_ZeroPointB[rsp]
        vpcmpeqw ymm12,ymm12,ymm12          # generate 256-bit word vector [0xFFFF]
        vpsrlw  ymm12,ymm12,15              # generate 256-bit word vector [0x0001]
        cmp     DWORD PTR .LGemmInt8KernelFrame_type[rsp],0
        je      .LCheckCountM4OrMore\@        # U8S8 AVX2 kernel requires extra registers

//
// Process CountM rows of the matrices.
//

.LCheckCountM6OrMore\@:
        cmp     r8,5
        ja      .LProcessCountM6\@
        je      .LProcessCountM5\@

.LCheckCountM4OrMore\@:
        cmp     r8,3
        ja      .LProcessCountM4\@
        je      .LProcessCountM3\@
        cmp     r8,1
        je      .LProcessCountM1\@

.LProcessCountM2\@:
        ProcessCountM 2, \ASigned\(), \BSigned\()

.LProcessCountM4\@:
        ProcessCountM 4, \ASigned\(), \BSigned\()

.LProcessCountM6\@:
        ProcessCountM 6, \ASigned\(), \BSigned\()

.LProcessCountM1\@:
        ProcessCountM 1, \ASigned\(), \BSigned\()

.LProcessCountM3\@:
        ProcessCountM 3, \ASigned\(), \BSigned\()

.LProcessCountM5\@:
        ProcessCountM 5, \ASigned\(), \BSigned\()

.endm

//
// Restore non-volatile registers and return.
//

.LExitKernel:
        vzeroupper

        pop     r13
        pop     r12
        pop     rbx
        pop     rbp
        ret

//
// Reduce code size for the various types of kernels by sharing the outer logic
// and switching on the selector codes (using sign bit to discriminate).
//

        FUNCTION_ENTRY MlasGemmU8S8KernelAvxVnni

        mov     eax,-1
        MlasGemmInt8KernelAvx2 0, 1

        FUNCTION_ENTRY MlasGemmU8U8KernelAvx2Vnni

        mov     eax,-1
        MlasGemmInt8KernelAvx2 0, 0

        FUNCTION_ENTRY MlasGemmU8U8KernelAvx2

        mov     eax,1
        MlasGemmInt8KernelAvx2 0, 0

        FUNCTION_ENTRY MlasGemmU8S8KernelAvx2

        xor     eax,eax
        MlasGemmInt8KernelAvx2 0, 1

        FUNCTION_ENTRY MlasGemmS8S8KernelAvx2Vnni

        mov     eax,-1
        MlasGemmInt8KernelAvx2 1, 1

        FUNCTION_ENTRY MlasGemmS8U8KernelAvx2Vnni

        mov     eax,-1
        MlasGemmInt8KernelAvx2 1, 0

        .end
