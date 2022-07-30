# This file is a part of Julia. License is MIT: https://julialang.org/license

module SPQRTests

using Test
using SparseArrays.SPQR
using SparseArrays.CHOLMOD
using LinearAlgebra: I, istriu, norm, qr, rank, rmul!, lmul!, Adjoint, Transpose
using SparseArrays: sparse, sprandn, spzeros, SparseMatrixCSC, _from_eachcol, _from_lmul

if Base.USE_GPL_LIBS

@testset "Sparse QR" begin
m, n = 100, 10
nn = 100

@test size(qr(sprandn(m, n, 0.1)).Q) == (m, m)

@testset "element type of A: $eltyA" for eltyA in (Float64, ComplexF64)
    if eltyA <: Real
        A = sparse([1:n; rand(1:m, nn - n)], [1:n; rand(1:n, nn - n)], randn(nn), m, n)
    else
        A = sparse([1:n; rand(1:m, nn - n)], [1:n; rand(1:n, nn - n)], complex.(randn(nn), randn(nn)), m, n)
    end

    F = qr(A)
    @test size(F) == (m,n)
    @test size(F, 1) == m
    @test size(F, 2) == n
    @test size(F, 3) == 1
    @test_throws ArgumentError size(F, 0)

    @testset "getindex" begin
        @test istriu(F.R)
        @test isperm(F.pcol)
        @test isperm(F.prow)
        @test_throws ErrorException F.T
    end

    @testset "apply Q" begin
        Q = F.Q
        Imm = Matrix{Float64}(I, m, m)
        @test Q' * (Q*Imm) ≈ Imm
        @test (Imm*Q) * Q' ≈ Imm

        # test that Q'Pl*A*Pr = R
        R0 = Q'*Array(A[F.prow, F.pcol])
        @test R0[1:n, :] ≈ F.R
        @test norm(R0[n + 1:end, :], 1) < 1e-12

        offsizeA = Matrix{Float64}(I, m+1, m+1)
        @test_throws DimensionMismatch lmul!(Q, offsizeA)
        @test_throws DimensionMismatch lmul!(adjoint(Q), offsizeA)
        @test_throws DimensionMismatch rmul!(offsizeA, Q)
        @test_throws DimensionMismatch rmul!(offsizeA, adjoint(Q))
    end

    @testset "element type of B: $eltyB" for eltyB in (Int, Float64, ComplexF64)
        if eltyB == Int
            B = rand(1:10, m, 2)
        elseif eltyB <: Real
            B = randn(m, 2)
        else
            B = complex.(randn(m, 2), randn(m, 2))
        end

        @inferred A\B
        @test A\B[:,1] ≈ Array(A)\B[:,1]
        @test A\B ≈ Array(A)\B
        @test_throws DimensionMismatch A\B[1:m-1,:]
        C, x = A[1:9, :], fill(eltyB(1), 9)
        @test C*(C\x) ≈ x # Underdetermined system
    end

    # Make sure that conversion to Sparse doesn't use SuiteSparse's symmetric flag
    @test qr(SparseMatrixCSC{eltyA}(I, 5, 5)) \ fill(eltyA(1), 5) == fill(1, 5)
end

@testset "basic solution of rank deficient ls" begin
    A = sprandn(m, 5, 0.9)*sprandn(5, n, 0.9)
    b = randn(m)
    xs = A\b
    xd = Array(A)\b

    # check that basic solution has more zeros
    @test count(!iszero, xs) < count(!iszero, xd)
    @test A*xs ≈ A*xd
end

@testset "Issue 26367" begin
    A = sparse([0.0 1 0 0; 0 0 0 0])
    @test Matrix(qr(A).Q) == Matrix(qr(Matrix(A)).Q) == Matrix(I, 2, 2)
    @test sparse(qr(A).Q) == sparse(qr(Matrix(A)).Q) == Matrix(I, 2, 2)
    @test (sparse(I, 2, 2) * F.Q)::SparseMatrixCSC == sparse(qr(A).Q) == sparse(I, 2, 2)
end

@testset "Issue 26368" begin
    A = sparse([0.0 1 0 0; 0 0 0 0])
    F = qr(A)
    @test (F.Q*F.R)::SparseMatrixCSC == A[F.prow,F.pcol]
end

@testset "select ordering overdetermined" begin
     A = sparse([1:n; rand(1:m, nn - n)], [1:n; rand(1:n, nn - n)], randn(nn), m, n)
     b = randn(m)
     xref = Array(A) \ b
     for ordering ∈ SPQR.ORDERINGS
         QR = qr(A, ordering=ordering)
         x = QR \ b
         @test x ≈ xref
     end
     @test_throws ErrorException qr(A, ordering=Int32(10))
end

@testset "select ordering underdetermined" begin
     A = sparse([1:n; rand(1:n, nn - n)], [1:n; rand(1:m, nn - n)], randn(nn), n, m)
     b = A * ones(m)
     for ordering ∈ SPQR.ORDERINGS
         QR = qr(A, ordering=ordering)
         x = QR \ b
         # x ≂̸ Array(A) \ b; LAPACK returns a min-norm x while SPQR returns a basic x
         @test A * x ≈ b
     end
     @test_throws ErrorException qr(A, ordering=Int32(10))
end

@testset "propertynames of QRSparse" begin
    A = sparse([0.0 1 0 0; 0 0 0 0])
    F = qr(A)
    @test propertynames(F) == (:R, :Q, :prow, :pcol)
    @test propertynames(F, true) == (:R, :Q, :prow, :pcol, :factors, :τ, :cpiv, :rpivinv)
end

@testset "rank" begin
    S = sprandn(10, 5, 1.0)*sprandn(5, 10, 1.0)
    @test rank(qr(S)) == 5
    @test rank(S) == 5
    @test all(iszero, (rank(qr(spzeros(10, i))) for i in 1:10))
    @test all(iszero, (rank(spzeros(10, i)) for i in 1:10))
end


@testset "sparse" begin
    A = I + sprandn(100, 100, 0.01)
    Q = qr(A).Q
    sQ = sparse(Q)
    @test sQ == sparse(Matrix(Q))
    @test sQ ≈ sparse(qr(Matrix(A)).Q)
end

end

end # Base.USE_GPL_LIBS

end # module
