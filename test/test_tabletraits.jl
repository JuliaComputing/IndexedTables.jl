using IndexedTables
using TableTraits
using NamedTuples
using Base.Test

@testset "TableTraits" begin

source_nds = NDSparse(Columns(a=[1,2,3]), Columns(b=[1.,2.,3.], c=["A","B","C"]))

@test isiterable(source_nds) == true

target_array_nds = collect(getiterator(source_nds))

@test length(target_array_nds) == 3
@test target_array_nds[1] == @NT(a=1, b=1., c="A")
@test target_array_nds[2] == @NT(a=2, b=2., c="B")
@test target_array_nds[3] == @NT(a=3, b=3., c="C")

source_array = [@NT(a=1,b=1.,c="A"), @NT(a=2,b=2.,c="B"), @NT(a=3,b=3.,c="C")]

it1 = NDSparse(source_array)
@test length(it1) == 3
@test it1[1,1.].c == "A"
@test it1[2,2.].c == "B"
@test it1[3,3.].c == "C"

it2 = NDSparse(source_array, idxcols=[:a])
@test length(it2) == 3
@test it2[1] == @NT(b=1., c="A")
@test it2[2] == @NT(b=2., c="B")
@test it2[3] == @NT(b=3., c="C")

it3 = NDSparse(source_array, datacols=[:b, :c])
@test length(it3) == 3
@test it3[1] == @NT(b=1., c="A")
@test it3[2] == @NT(b=2., c="B")
@test it3[3] == @NT(b=3., c="C")

it4 = NDSparse([(1=>"A"), (2=>"B")])
@test length(it4) == 2
@test it4[1] == "A"
@test it4[2] == "B"

source_nt = table([1,2,3],[1.,2.,3.],["A","B","C"], names=[:a,:b,:c])

target_array_nt = collect(getiterator(source_nt))

@test length(target_array_nt) == 3
@test target_array_nt[1] == @NT(a=1, b=1., c="A")
@test target_array_nt[2] == @NT(a=2, b=2., c="B")
@test target_array_nt[3] == @NT(a=3, b=3., c="C")

it4 = table(source_array, copy=true)
@test length(it4) == 3
@test it4[1] == @NT(a=1,b=1.,c="A")
@test it4[2] == @NT(a=2,b=2.,c="B")
@test it4[3] == @NT(a=3,b=3.,c="C")

# Use a Set to really hit the iterator constructor
as_set = Set(source_array)
it4 = table(as_set, copy=true)
@test length(it4) == 3
@test contains(==, as_set, it4[1])
@test contains(==, as_set, it4[2])
@test contains(==, as_set, it4[3])

@testset "avoid too narrow dict value type" begin
    # The array constructor
    @test table([@NT(col1 = "A")], pkey = [1]) ==
            table(["A"], names = [:col1], pkey = [1])

    # The iterator constructor
    @test table(Iterators.repeated(@NT(col1 = "A"), 2), pkey = [1]) ==
            table(["A", "A"], names = [:col1], pkey = [1])
end

# Non NamedTuples iterators

@test table([(1, 2), (3, 4)]) == table([1, 3], [2, 4])
@test table([@NT(a=1) => @NT(b=2)]) == table([1], [2], names = [:a, :b], pkey = :a)

end
