using Base.Test
using IndexedTables
using PooledArrays
using NamedTuples

let a = Columns([1,2,1],["foo","bar","baz"]),
    b = Columns([2,1,1],["bar","baz","foo"]),
    c = Columns([1,1,2],["foo","baz","bar"])
    @test a != b
    @test a != c
    @test b != c
    sort!(a)
    @test sort(b) == a
    sort!(b); sort!(c)
    @test a == b == c
    @test size(a) == size(b) == size(c) == (3,)
    @test eltype(a) == Tuple{Int,String}
    @test length(similar(a)) == 3
end

let c = Columns([1,1,1,2,2], [1,2,4,3,5]),
    d = Columns([1,1,2,2,2], [1,3,1,4,5]),
    e = Columns([1,1,1], sort([rand(),0.5,rand()])),
    f = Columns([1,1,1], sort([rand(),0.5,rand()]))
    @test merge(IndexedTable(c,ones(5)),IndexedTable(d,ones(5))).index == Columns([1,1,1,1,2,2,2,2],[1,2,3,4,1,3,4,5])
    @test eltype(merge(IndexedTable(c,Columns(ones(Int, 5))),IndexedTable(d,Columns(ones(Float64, 5)))).data) == Tuple{Float64}
    @test eltype(merge(IndexedTable(c,Columns(x=ones(Int, 5))),IndexedTable(d,Columns(x=ones(Float64, 5)))).data) == @NT(x){Float64}
    @test length(merge(IndexedTable(e,ones(3)),IndexedTable(f,ones(3)))) == 5
    @test vcat(Columns(x=[1]), Columns(x=[1.0])) == Columns(x=[1,1.0])
    @test vcat(Columns(x=PooledArray(["x"])), Columns(x=["y"])) == Columns(x=["x", "y"])

    @test summary(c) == "Columns{Tuple{Int64,Int64}}"
end

let
    x = Columns([1], [2.0])
    @test map(pick(2), x) == [2.0]
    @test map(@pick(2), x) == Columns([2.0])
    @test map(@pick(2,1), x) == Columns([2.0], [1])

    y = Columns(x=[1], y=[2.0])
    @test map(pick(2), y) == [2.0]
    @test map(@pick(2), y) == Columns([2.0])
    @test map(@pick(y), y) == Columns(y=[2.0])
    @test map(@pick(2,1), y) == Columns([2.0], [1])
    @test map(@pick(y,x), y) == Columns(y=[2.0], x=[1])
end

let c = Columns([1,1,1,2,2], [1,2,4,3,5]),
    d = Columns([1,1,2,2,2], [1,3,1,4,5]),
    e = Columns([1,1,1], sort([rand(),0.5,rand()])),
    f = Columns([1,1,1], sort([rand(),0.5,rand()]))
    @test map(+,IndexedTable(c,ones(5)),IndexedTable(d,ones(5))).index == Columns([1,2],[1,5])
    @test length(map(+,IndexedTable(e,ones(3)),IndexedTable(f,ones(3)))) == 1
    @test eltype(c) == Tuple{Int,Int}
end

srand(123)
A = IndexedTable(rand(1:3,10), rand('A':'F',10), map(UInt8,rand(1:3,10)), collect(1:10), randn(10))
B = IndexedTable(map(UInt8,rand(1:3,10)), rand('A':'F',10), rand(1:3,10), randn(10))
C = IndexedTable(map(UInt8,rand(1:3,10)), rand(1:3,10), rand(1:3,10), randn(10))

let a = IndexedTable([12,21,32], [52,41,34], [11,53,150]), b = IndexedTable([12,23,32], [52,43,34], [56,13,10])
    @test eltype(a) == Int
    @test sum(a) == 214

    c = similar(a)
    @test typeof(c) == typeof(a)
    @test length(c.index) == 0

    c = copy(a)
    @test typeof(c) == typeof(a)
    @test length(c.index) == length(a.index)
    empty!(c)
    @test length(c.index) == 0

    c = convertdim(convertdim(a, 1, Dict(12=>10, 21=>20, 32=>20)), 2, Dict(52=>50, 34=>20, 41=>20), -)
    @test c[20,20] == 97

    c = map(+, a, b)
    @test length(c.index) == 2
    @test sum(map(-, c, c)) == 0

    @test map(iseven, a) == IndexedTable([12,21,32], [52,41,34], [false,false,true])
end

let S = spdiagm(1:5)
    nd = convert(IndexedTable, S)
    @test sum(S) == sum(nd) == sum(convert(IndexedTable, full(S)))

    @test sum(broadcast(+, 10, nd)) == (sum(nd) + 10*nnz(S))
    @test sum(broadcast(+, nd, 10)) == (sum(nd) + 10*nnz(S))
    @test sum(broadcast(+, nd, nd)) == 2*(sum(nd))

    nd[1:5,1:5] = 2
    @test nd == convert(IndexedTable, spdiagm(fill(2, 5)))
end

let S = sprand(10,10,.1), v = rand(10)
    nd = convert(IndexedTable, S)
    ndv = convert(IndexedTable,v)
    @test broadcast(*, nd, ndv) == convert(IndexedTable, S .* v)
    # test matching dimensions by name
    ndt0 = convert(IndexedTable, sparse(S .* (v')))
    ndt = IndexedTable(Columns(a=ndt0.index.columns[1], b=ndt0.index.columns[2]), ndt0.data, presorted=true)
    @test broadcast(*,
                    IndexedTable(Columns(a=nd.index.columns[1], b=nd.index.columns[2]), nd.data),
                    IndexedTable(Columns(b=ndv.index.columns[1]), ndv.data)) == ndt
end

let a = rand(10), b = rand(10), c = rand(10)
    @test IndexedTable(a, b, c) == IndexedTable(a, b, c)
    c2 = copy(c)
    c2[1] += 1
    @test IndexedTable(a, b, c) != IndexedTable(a, b, c2)
    b2 = copy(b)
    b2[1] += 1
    @test IndexedTable(a, b, c) != IndexedTable(a, b2, c)
end

let a = rand(10), b = rand(10), c = rand(10), d = rand(10)
    local nd = IndexedTable(a,b,c,d)
    @test permutedims(nd,[3,1,2]) == IndexedTable(c,a,b,d)
    @test_throws ArgumentError permutedims(nd, [1,2])
    @test_throws ArgumentError permutedims(nd, [1,3])
    @test_throws ArgumentError permutedims(nd, [1,2,2])
end

let r=1:5, s=1:2:5
    A = IndexedTable([r;], [r;], [r;])
    @test A[s, :] == IndexedTable([s;], [s;], [s;])
    @test_throws ErrorException A[s, :, :]
end

let a = IndexedTable([1,2,2,2], [1,2,3,4], [10,9,8,7])
    @test a[1,1] == 10
    @test a[2,3] == 8
    #@test_throws ErrorException a[2]
    @test a[2,:] == IndexedTable([2,2,2], [2,3,4], [9,8,7])
    @test a[:,1] == IndexedTable([1], [1], [10])
    @test collect(where(a, 2, :)) == [9,8,7]
    @test collect(pairs(a)) == [(1,1)=>10, (2,2)=>9, (2,3)=>8, (2,4)=>7]
    @test first(pairs(a, :, 3)) == ((2,3)=>8)

    update!(x->x+10, a, 2, :)
    @test a == IndexedTable([1,2,2,2], [1,2,3,4], [10,19,18,17])

    a[2,2:3] = 77
    @test a == IndexedTable([1,2,2,2], [1,2,3,4], [10,77,77,17])
end

let a = IndexedTable([1,2,2,2], [1,2,3,4], zeros(4))
    a2 = copy(a); a3 = copy(a)
    #a[2,:] = 1
    #@test a == IndexedTable([1,2,2,2], [1,2,3,4], Float64[0,1,1,1])
    a2[2,[2,3]] = 1
    @test a2 == IndexedTable([1,2,2,2], [1,2,3,4], Float64[0,1,1,0])
    a3[2,[2,3]] = [8,9]
    @test a3 == IndexedTable([1,2,2,2], [1,2,3,4], Float64[0,8,9,0])
end

# issue #15
let a = IndexedTable([1,2,3,4], [1,2,3,4], [1,2,3,4])
    a[5,5] = 5
    a[5,5] = 6
    @test a[5,5] == 6
end

let a = IndexedTable([1,2,2,3,4,5], [1,2,2,3,4,5], [1,2,20,3,4,5], agg=+)
    @test a == IndexedTable([1,2,3,4,5], [1,2,3,4,5], [1,22,3,4,5])
end

let a = rand(5,5,5)
    for dims in ([2,3], [1], [2])
        r = squeeze(reducedim(+, a, dims), (dims...,))
        asnd = convert(IndexedTable,a)
        b = reducedim(+, asnd, dims)
        bv = reducedim_vec(sum, asnd, dims)
        c = convert(IndexedTable, r)
        @test b.index == c.index == bv.index
        @test b.data ≈ c.data
        @test bv.data ≈ c.data
    end
    @test_throws ArgumentError reducedim(+, convert(IndexedTable,a), [1,2,3])
end

for a in (rand(2,2), rand(3,5))
    nd = convert(IndexedTable, a)
    @test nd == convert(IndexedTable, sparse(a))
    for (I,d) in zip(nd.index, nd.data)
        @test a[I...] == d
    end
end

_colnames(x::IndexedTable) = keys(x.index.columns)

@test _colnames(IndexedTable(ones(2),ones(2),ones(2),names=[:a,:b])) == [:a, :b]
@test _colnames(IndexedTable(Columns(x=ones(2),y=ones(2)), ones(2))) == [:x, :y]

let x = IndexedTable(Columns(x = [1,2,3], y = [4,5,6], z = [7,8,9]), [10,11,12])
    names = [:x, :y, :z]
    @test _colnames(x) == names
    @test _colnames(filter(a->a==11, x)) == names
    @test _colnames(select(x, :z, :x)) == [:z, :x]
    @test _colnames(select(x, :y)) == [:y]
    @test _colnames(select(x, :x=>a->a>1, :z=>a->a>7)) == names
    @test _colnames(x[1:2, 4:5, 8:9]) == names
    @test convertdim(x, :y, a->0) == IndexedTable(Columns(x=[1,2,3], y=[0,0,0], z=[7,8,9]), [10,11,12])
    @test convertdim(x, :y, a->0, name=:yy) == IndexedTable(Columns(x=[1,2,3], yy=[0,0,0], z=[7,8,9]), [10,11,12])
end

# test showing
@test repr(IndexedTable([1,2,3],[3,2,1],Float64[4,5,6])) == """
─────┬────
1  3 │ 4.0
2  2 │ 5.0
3  1 │ 6.0"""

@test repr(IndexedTable(Columns(a=[1,2,3],test=[3,2,1]),Float64[4,5,6])) == """
a  test │ 
────────┼────
1  3    │ 4.0
2  2    │ 5.0
3  1    │ 6.0"""

@test repr(IndexedTable(Columns(a=[1,2,3],test=[3,2,1]),Columns(x=Float64[4,5,6],y=[9,8,7]))) == """
a  test │ x    y
────────┼───────
1  3    │ 4.0  9
2  2    │ 5.0  8
3  1    │ 6.0  7"""

@test repr(IndexedTable([1,2,3],[3,2,1],Columns(x=Float64[4,5,6],y=[9,8,7]))) == """
     │ x    y
─────┼───────
1  3 │ 4.0  9
2  2 │ 5.0  8
3  1 │ 6.0  7"""

@test repr(IndexedTable([1:21;],ones(Int,21))) == """
───┬──
1  │ 1
2  │ 1
3  │ 1
4  │ 1
5  │ 1
6  │ 1
7  │ 1
8  │ 1
9  │ 1
10 │ 1
   ⋮
12 │ 1
13 │ 1
14 │ 1
15 │ 1
16 │ 1
17 │ 1
18 │ 1
19 │ 1
20 │ 1
21 │ 1"""

let x = Columns([6,5,4,3,2,2,1],[4,4,4,4,4,4,4],[1,2,3,4,5,6,7])
    @test issorted(x[sortperm(x)])
end

let x = IndexedTable([1,2],[3,4],[:a,:b],[3,5])
    @test x[1,:,:a] == IndexedTable([1],[3],[:a],[3])
end

# issue #42
using Base.Dates
let hitemps = IndexedTable([fill("New York",3); fill("Boston",3)],
                           repmat(Date(2016,7,6):Date(2016,7,8), 2),
                           [91,89,91,95,83,76])
    @test hitemps[:, Date(2016,7,8)] == IndexedTable(["New York", "Boston"],
                                                     fill(Date(2016,7,8), 2),
                                                     [91,76])
end
