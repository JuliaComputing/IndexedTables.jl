using Compat

import Base:
    linearindexing, push!, size, sort, sort!, permute!, issorted, sortperm,
    summary, resize!, vcat, serialize, deserialize, append!, copy!, view

export Columns, colnames, ncols, ColDict, insertafter!, insertbefore!, @cols, setcol, pushcol, popcol, insertcol, insertcolafter, insertcolbefore, renamecol
export map_rows
export All, Not, Between, Keys

"""
A type that stores an array of tuples as a tuple of arrays.

# Fields:

- `columns`: a tuple or named tuples of arrays. Also `columns(x)`
"""
struct Columns{D<:Union{Tup, Pair}, C<:Union{Tup, Pair}} <: AbstractVector{D}
    columns::C

    function Columns{D,C}(c) where {D<:Tup,C<:Tup}
        length(c) > 0 || error("must have at least one column")
        n = length(c[1])
        for i = 2:length(c)
            length(c[i]) == n || error("all columns must have same length")
        end
        new{D,C}(c)
    end

    function Columns{D,C}(c::Pair) where {D<:Pair,C<:Pair{<:AbstractVector, <:AbstractVector}}
        length(c.first) == length(c.second) || error("all columns must have same length")
        new{D,C}(c)
    end
end

function Columns(cols::AbstractVector...; names::Union{Vector,Tuple{Vararg{Any}},Void}=nothing)
    if isa(names, Void) || any(x->!(x isa Symbol), names)
        Columns{eltypes(typeof(cols)),typeof(cols)}(cols)
    else
        dt = eval(:(@NT($(names...)))){map(eltype, cols)...}
        ct = eval(:(@NT($(names...)))){map(typeof, cols)...}
        Columns{dt,ct}(ct(cols...))
    end
end

Columns(; pairs...) = Columns(map(x->x[2],pairs)..., names=Symbol[x[1] for x in pairs])

Columns(c::Union{Tup, Pair}) = Columns{eltypes(typeof(c)),typeof(c)}(c)

# IndexedTable-like API

"""
    colnames(itr)

Returns the names of the "columns" in `itr`.

# Examples:

```jldoctest
julia> colnames([1,2,3])
1-element Array{Int64,1}:
 1

julia> colnames(Columns([1,2,3], [3,4,5]))
2-element Array{Int64,1}:
 1
 2

julia> colnames(table([1,2,3], [3,4,5]))
2-element Array{Int64,1}:
 1
 2

julia> colnames(Columns(x=[1,2,3], y=[3,4,5]))
2-element Array{Symbol,1}:
 :x
 :y

julia> colnames(table([1,2,3], [3,4,5], names=[:x,:y]))
2-element Array{Symbol,1}:
 :x
 :y

julia> colnames(ndsparse(Columns(x=[1,2,3]), Columns(y=[3,4,5])))
2-element Array{Symbol,1}:
 :x
 :y

julia> colnames(ndsparse(Columns(x=[1,2,3]), [3,4,5]))
2-element Array{Any,1}:
 :x
 1
 2

julia> colnames(ndsparse(Columns(x=[1,2,3]), [3,4,5]))
2-element Array{Any,1}:
 :x
 2

julia> colnames(ndsparse(Columns([1,2,3], [4,5,6]), Columns(x=[6,7,8])))
3-element Array{Any,1}:
 1
 2
 :x

julia> colnames(ndsparse(Columns(x=[1,2,3]), Columns([3,4,5],[6,7,8])))
3-element Array{Any,1}:
 :x
 2
 3
```
"""
function colnames end

Base.@pure colnames(t::AbstractVector) = [1]
columns(v::AbstractVector) = v

Base.@pure colnames(t::Columns) = fieldnames(eltype(t))
Base.@pure colnames(t::Columns{<:Pair, <:Pair}) = colnames(t.columns.first) => colnames(t.columns.second)

"""
`columns(itr[, select::Selection])`

Select one or more columns from an iterable of rows as a tuple of vectors.

`select` specifies which columns to select. See [`Selection convention`](@ref select) for possible values. If unspecified, returns all columns.

`itr` can be `NDSparse`, `Columns` and `AbstractVector`, and their distributed counterparts.

# Examples

```jldoctest
julia> t = table([1,2],[3,4], names=[:x,:y])
Table with 2 rows, 2 columns:
x  y
────
1  3
2  4

julia> columns(t)
(x = [1, 2], y = [3, 4])

julia> columns(t, :x)
2-element Array{Int64,1}:
 1
 2

julia> columns(t, (:x,))
(x = [1, 2])

julia> columns(t, (:y,:x=>-))
(y = [3, 4], x = [-1, -2])
```
"""
function columns end

columns(c) = error("no columns defined for $(typeof(c))")
columns(c::Columns) = c.columns

# Array-like API

eltype{D,C}(::Type{Columns{D,C}}) = D
length(c::Columns) = length(c.columns[1])
length(c::Columns{<:Pair, <:Pair}) = length(c.columns.first)
ndims(c::Columns) = 1

"""
`ncols(itr)`

Returns the number of columns in `itr`.

```jldoctest
julia> ncols([1,2,3])
1

julia> d = ncols(rows(([1,2,3],[4,5,6])))
2

julia> ncols(table(([1,2,3],[4,5,6])))
2

julia> ncols(table(@NT(x=[1,2,3],y=[4,5,6])))
2

julia> ncols(ndsparse(d, [7,8,9]))
3
```
"""
function ncols end
ncols(c::Columns) = nfields(typeof(c.columns))
ncols(c::Columns{<:Pair, <:Pair}) = ncols(c.columns.first) => ncols(c.columns.second)
ncols(c::AbstractArray) = 1

size(c::Columns) = (length(c),)
Base.IndexStyle(::Type{<:Columns}) = IndexLinear()
summary(c::Columns{D}) where {D<:Tuple} = "$(length(c))-element Columns{$D}"

empty!(c::Columns) = (foreach(empty!, c.columns); c)
empty!(c::Columns{<:Pair, <:Pair}) = (foreach(empty!, c.columns.first.columns); foreach(empty!, c.columns.second.columns); c)

function similar(c::Columns{D,C}) where {D,C}
    cols = _map(similar, c.columns)
    Columns{D,typeof(cols)}(cols)
end

function similar(c::Columns{D,C}, n::Integer) where {D,C}
    cols = _map(a->similar(a,n), c.columns)
    Columns{D,typeof(cols)}(cols)
end

function Base.similar{T<:Columns}(::Type{T}, n::Int)::T
    T_cols = T.parameters[2]
    f = T_cols <: Tuple ? tuple : T_cols
    T(f(map(t->similar(t, n), T.parameters[2].parameters)...))
end

function convert{N}(::Type{Columns}, x::AbstractArray{<:NTuple{N,Any}})
    eltypes = (eltype(x).parameters...)
    copy!(Columns(map(t->Vector{t}(length(x)), eltypes)), x)
end

function convert(::Type{Columns}, x::AbstractArray{<:NamedTuple})
    eltypes = (eltype(x).parameters...)
    copy!(Columns(map(t->Vector{t}(length(x)), eltypes)..., names=fieldnames(eltype(x))), x)
end


getindex(c::Columns{D}, i::Integer) where {D<:Tuple} = ith_all(i, c.columns)
getindex(c::Columns{D}, i::Integer) where {D<:NamedTuple} = D(ith_all(i, c.columns)...)
getindex(c::Columns{D}, i::Integer) where {D<:Pair} = getindex(c.columns.first, i) => getindex(c.columns.second, i)

getindex(c::Columns, p::AbstractVector) = Columns(_map(c->c[p], c.columns))

view(c::Columns, I) = Columns(_map(a->view(a, I), c.columns))

@inline setindex!(I::Columns, r::Union{Tup, Pair}, i::Integer) = (foreach((c,v)->(c[i]=v), I.columns, r); I)

@inline push!(I::Columns, r::Union{Tup, Pair}) = (foreach(push!, I.columns, r); I)

append!(I::Columns, J::Columns) = (foreach(append!, I.columns, J.columns); I)

copy!(I::Columns, J::Columns) = (foreach(copy!, I.columns, J.columns); I)

resize!(I::Columns, n::Int) = (foreach(c->resize!(c,n), I.columns); I)

_sizehint!(c::Columns, n::Integer) = (foreach(c->_sizehint!(c,n), c.columns); c)

function ==(x::Columns, y::Columns)
    nc = length(x.columns)
    length(y.columns) == nc || return false
    fieldnames(eltype(x)) == fieldnames(eltype(y)) || return false
    n = length(x)
    length(y) == n || return false
    for i in 1:nc
        x.columns[i] == y.columns[i] || return false
    end
    return true
end

==(x::Columns{<:Pair}, y::Columns) = false
==(x::Columns, y::Columns{<:Pair}) = false
==(x::Columns{<:Pair}, y::Columns{<:Pair}) = (x.columns.first == y.columns.first) && (x.columns.second == y.columns.second)

function _strip_pair(c::Columns{<:Pair})
    f, s = map(columns, c.columns)
    (f isa AbstractVector) && (f = (f,))
    (s isa AbstractVector) && (s = (s,))
    Columns(f..., s...)
end

function sortperm(c::Columns)
    cols = c.columns
    x = cols[1]
    if x isa Vector{String}
        pa = PooledArray(x)
        p = sortperm_fast(pa)
    else
        p = sortperm_fast(x)
    end
    if length(cols) > 1
        y = cols[2]
        refine_perm!(p, cols, 1, x, y, 1, length(x))
    end
    return p
end

sortperm(c::Columns{<:Pair}) = sortperm(_strip_pair(c))

issorted(c::Columns) = issorted(1:length(c), lt=(x,y)->rowless(c, x, y))
issorted(c::Columns{<:Pair}) = issorted(_strip_pair(c))

# assuming x[p] is sorted, sort by remaining columns where x[p] is constant
function refine_perm!(p, cols, c, x, y, lo, hi)
    temp = similar(p, 0)
    order = Base.Order.By(j->(@inbounds k=y[j]; k))
    nc = length(cols)
    i = lo
    while i < hi
        i1 = i+1
        @inbounds while i1 <= hi && roweq(x, p[i1], p[i])
            i1 += 1
        end
        i1 -= 1
        if i1 > i
            sort_sub_by!(p, i, i1, y, order, temp)
            if c < nc-1
                z = cols[c+2]
                refine_perm!(p, cols, c+1, y, z, i, i1)
            end
        end
        i = i1+1
    end
end

function permute!(c::Columns, p::AbstractVector)
    for v in c.columns
        copy!(v, v[p])
    end
    return c
end
permute!(c::Columns{<:Pair}, p::AbstractVector) = (permute!(c.columns.first, p); permute!(c.columns.second, p); c)
sort!(c::Columns) = permute!(c, sortperm(c))
sort(c::Columns) = c[sortperm(c)]

function Base.vcat(c::Columns, cs::Columns...)
    fns = map(fieldnames, (map(x->x.columns, (c, cs...))))
    f1 = fns[1]
    for f2 in fns[2:end]
        if f1 != f2
            errfields = join(map(string, fns), ", ", " and ")
            throw(ArgumentError("Cannot concatenate columns with fields $errfields"))
        end
    end
    Columns(map(vcat, map(x->x.columns, (c,cs...))...))
end

function Base.vcat(c::Columns{<:Pair}, cs::Columns{<:Pair}...)
    Columns(vcat(c.columns.first, (x.columns.first for x in cs)...) =>
            vcat(c.columns.second, (x.columns.second for x in cs)...))
end


abstract type SerializedColumns end

function serialize(s::AbstractSerializer, c::Columns)
    Base.Serializer.serialize_type(s, SerializedColumns)
    serialize(s, eltype(c) <: NamedTuple)
    serialize(s, isa(c.columns, NamedTuple))
    serialize(s, fieldnames(c.columns))
    for col in c.columns
        serialize(s, col)
    end
end

function deserialize(s::AbstractSerializer, ::Type{SerializedColumns})
    Dnamed = deserialize(s)
    Cnamed = deserialize(s)
    fn = deserialize(s)
    cols = Any[ deserialize(s) for i = 1:length(fn) ]
    if Cnamed
        c = Columns(cols..., names = fn)
        if !Dnamed
            dt = eltypes(typeof((c.columns...,)))
            c = Columns{dt,typeof(c.columns)}(c.columns)
        end
    else
        c = Columns(cols...)
    end
    return c
end

# fused indexing operations
# these can be implemented for custom vector types like PooledVector where
# you can get big speedups by doing indexing and an operation in one step.

@inline cmpelts(a, i, j) = (@inbounds x=cmp(a[i], a[j]); x)
@inline copyelt!(a, i, j) = (@inbounds a[i] = a[j])
@inline copyelt!(a, i, b, j) = (@inbounds a[i] = b[j])

@inline cmpelts(a::PooledArray, i, j) = (x=cmp(a.refs[i],a.refs[j]); x)
@inline copyelt!(a::PooledArray, i, j) = (a.refs[i] = a.refs[j])

# row operations

copyrow!(I::Columns, i, src) = foreach(c->copyelt!(c, i, src), I.columns)
copyrow!(I::Columns, i, src::Columns, j) = foreach((c1,c2)->copyelt!(c1, i, c2, j), I.columns, src.columns)
copyrow!(I::AbstractArray, i, src::AbstractArray, j) = (@inbounds I[i] = src[j])
pushrow!(to::Columns, from::Columns, i) = foreach((a,b)->push!(a, b[i]), to.columns, from.columns)
pushrow!(to::AbstractArray, from::AbstractArray, i) = push!(to, from[i])

@generated function rowless{D,C}(c::Columns{D,C}, i, j)
    N = length(C.parameters)
    ex = :(cmpelts(getfield(c.columns,$N), i, j) < 0)
    for n in N-1:-1:1
        ex = quote
            let d = cmpelts(getfield(c.columns,$n), i, j)
                (d == 0) ? ($ex) : (d < 0)
            end
        end
    end
    ex
end

@generated function roweq{D,C}(c::Columns{D,C}, i, j)
    N = length(C.parameters)
    ex = :(cmpelts(getfield(c.columns,1), i, j) == 0)
    for n in 2:N
        ex = :(($ex) && (cmpelts(getfield(c.columns,$n), i, j)==0))
    end
    ex
end

@inline roweq(x::AbstractVector, i, j) = x[i] == x[j]

# uses number of columns from `d`, assuming `c` has more or equal
# dimensions, for broadcast joins.
@generated function rowcmp{D}(c::Columns, i, d::Columns{D}, j)
    N = length(D.parameters)
    ex = :(cmp(getfield(c.columns,$N)[i], getfield(d.columns,$N)[j]))
    for n in N-1:-1:1
        ex = quote
            let k = cmp(getfield(c.columns,$n)[i], getfield(d.columns,$n)[j])
                (k == 0) ? ($ex) : k
            end
        end
    end
    ex
end

@inline function rowcmp(c::AbstractVector, i, d::AbstractVector, j)
    cmp(c[i], d[j])
end

# test that the row on the right is "as of" the row on the left, i.e.
# all columns are equal except left >= right in last column.
# Could be generalized to some number of trailing columns, but I don't
# know whether that has applications.
@generated function row_asof{D,C}(c::Columns{D,C}, i, d::Columns{D,C}, j)
    N = length(C.parameters)
    if N == 1
        ex = :(!isless(getfield(c.columns,1)[i], getfield(d.columns,1)[j]))
    else
        ex = :(isequal(getfield(c.columns,1)[i], getfield(d.columns,1)[j]))
    end
    for n in 2:N
        if N == n
            ex = :(($ex) && !isless(getfield(c.columns,$n)[i], getfield(d.columns,$n)[j]))
        else
            ex = :(($ex) && isequal(getfield(c.columns,$n)[i], getfield(d.columns,$n)[j]))
        end
    end
    ex
end

# map

"""
`map_rows(f, c...)`

Transform collection `c` by applying `f` to each element. For multiple collection arguments, apply `f`
elementwise. Collect output as `Columns` if `f` returns
`Tuples` or `NamedTuples` with constant fields, as `Array` otherwise.

# Examples

```jldoctest map_rows
julia> map_rows(i -> @NT(exp = exp(i), log = log(i)), 1:5)
5-element IndexedTables.Columns{NamedTuples._NT_exp_log{Float64,Float64},NamedTuples._NT_exp_log{Array{Float64,1},Array{Float64,1}}}:
 (exp = 2.71828, log = 0.0)
 (exp = 7.38906, log = 0.693147)
 (exp = 20.0855, log = 1.09861)
 (exp = 54.5982, log = 1.38629)
 (exp = 148.413, log = 1.60944)
```
"""
function map_rows(f, iters...)
    collect_columns(f(i...) for i in zip(iters...))
end

# 1-arg case
map_rows(f, iter) = collect_columns(f(i) for i in iter)

## Special selectors to simplify column selector

"""
`All(cols)`

Select the union of the selections in `cols`. If `cols == ()`, select all columns.

# Examples

```jldoctest All
julia> t = table([1,1,2,2], [1,2,1,2], [1,2,3,4], [0, 0, 0, 0],
                        names=[:a,:b,:c,:d])
Table with 4 rows, 4 columns:
a  b  c  d
──────────
1  1  1  0
1  2  2  0
2  1  3  0
2  2  4  0

julia> select(t, All(:a, (:b, :c)))
Table with 4 rows, 3 columns:
a  b  c
───────
1  1  1
1  2  2
2  1  3
2  2  4

julia> select(t, All())
Table with 4 rows, 4 columns:
a  b  c  d
──────────
1  1  1  0
1  2  2  0
2  1  3  0
2  2  4  0
```
"""
struct All{T}
    cols::T
end

All(args...) = All(args)

"""
`Not(cols)`

Select the complementary of the selection in `cols`. `Not` can accept several arguments,
in which case it returns the complementary of the union of the selections.

# Examples

```jldoctest Not
julia> t = table([1,1,2,2], [1,2,1,2], [1,2,3,4],
                        names=[:a,:b,:c], pkey = (:a, :b))
Table with 4 rows, 3 columns:
a  b  c
───────
1  1  1
1  2  2
2  1  3
2  2  4

julia> select(t, Keys())
Table with 4 rows, 2 columns:
b  c
────
1  1
2  2
1  3
2  4

julia> select(t, Not(:a, (:a, :b)))
Table with 4 rows, 1 columns:
c
─
1
2
3
4
```
"""
struct Not{T}
    cols::T
end

Not(args...) = Not(All(args))

"""
`Keys()`

Select the primary keys.

# Examples

```jldoctest Keys
julia> t = table([1,1,2,2], [1,2,1,2], [1,2,3,4],
                               names=[:a,:b,:c], pkey = (:a, :b))
Table with 4 rows, 3 columns:
a  b  c
───────
1  1  1
1  2  2
2  1  3
2  2  4

julia> select(t, Keys())
Table with 4 rows, 2 columns:
a  b
────
1  1
1  2
2  1
2  2
```
"""
struct Keys; end

"""
`Between(first, last)`

Select the columns between `first` and `last`.

# Examples

```jldoctest Between
julia> t = table([1,1,2,2], [1,2,1,2], [1,2,3,4], ["a", "b", "c", "d"],
                                      names=[:a,:b,:c, :d])
Table with 4 rows, 4 columns:
a  b  c  d
────────────
1  1  1  "a"
1  2  2  "b"
2  1  3  "c"
2  2  4  "d"

julia> select(t, Between(:b, :d))
Table with 4 rows, 3 columns:
b  c  d
─────────
1  1  "a"
2  2  "b"
1  3  "c"
2  4  "d"
```
"""
struct Between{T1 <: Union{Int, Symbol}, T2 <: Union{Int, Symbol}}
    first::T1
    last::T2
end

const SpecialSelector = Union{Not, All, Keys, Between, Function, Regex}

hascolumns(t, s) = true
hascolumns(t, s::Symbol) = s in colnames(t)
hascolumns(t, s::Int) = s in 1:length(columns(t))
hascolumns(t, s::Tuple) = all(hascolumns(t, x) for x in s)
hascolumns(t, s::Not) = hascolumns(t, s.cols)
hascolumns(t, s::Between) = hascolumns(t, s.first) && hascolumns(t, s.last)
hascolumns(t, s::All) = all(hascolumns(t, x) for x in s.cols)

lowerselection(t, s)                     = s
lowerselection(t, s::Union{Int, Symbol}) = colindex(t, s)
lowerselection(t, s::Tuple)              = map(x -> lowerselection(t, x), s)
lowerselection(t, s::Not)                = excludecols(t, lowerselection(t, s.cols))
lowerselection(t, s::Keys)               = lowerselection(t, IndexedTables.pkeynames(t))
lowerselection(t, s::Between)            = Tuple(colindex(t, s.first):colindex(t, s.last))
lowerselection(t, s::Function)           = colindex(t, Tuple(filter(s, colnames(t))))
lowerselection(t, s::Regex)              = lowerselection(t, x -> ismatch(s, string(x)))

function lowerselection(t, s::All)
    s.cols == () && return lowerselection(t, valuenames(t))
    ls = (isa(i, Tuple) ? i : (i,) for i in lowerselection(t, s.cols))
    ls |> Iterators.flatten |> union |> Tuple
end

### Iteration API

# For `columns(t, names)` and `rows(t, ...)` to work, `t`
# needs to support `colnames` and `columns(t)`

Base.@pure function colindex(t, col::Tuple)
    fns = colnames(t)
    map(x -> _colindex(fns, x), col)
end

Base.@pure function colindex(t, col)
    _colindex(colnames(t), col)
end

function colindex(t, col::SpecialSelector)
    colindex(t, lowerselection(t, col))
end

function _colindex(fnames::AbstractArray, col, default=nothing)
    if isa(col, Int) && 1 <= col <= length(fnames)
        return col
    elseif isa(col, Symbol)
        idx = findfirst(fnames, col)
        idx > 0 && return idx
    elseif isa(col, Pair{<:Any, <:AbstractArray})
        return 0
    elseif isa(col, Tuple)
        return 0
    elseif isa(col, Pair{Symbol, <:Pair}) # recursive pairs
        return _colindex(fnames, col[2])
    elseif isa(col, Pair{<:Any, <:Any})
        return _colindex(fnames, col[1])
    elseif isa(col, AbstractArray)
        return 0
    end
    default !== nothing ? default : error("column $col not found.")
end

# const ColPicker = Union{Int, Symbol, Pair{Symbol=>Function}, Pair{Symbol=>AbstractVector}, AbstractVector}
column(c, x) = columns(c)[colindex(c, x)]

# optimized method
@inline function column(c::Columns, x::Union{Int, Symbol})
    getfield(c.columns, x)
end

column(t, a::AbstractArray) = a
column(t, a::Pair{Symbol, <:AbstractArray}) = column(t, a[2])
column(t, a::Pair{Symbol, <:Pair}) = rows(t, a[2]) # renaming a selection
column(t, a::Pair{<:Any, <:Any}) = map(a[2], rows(t, a[1]))
column(t, s::SpecialSelector) = rows(t, lowerselection(t, s))

function columns(c, sel::Union{Tuple, SpecialSelector})
    which = lowerselection(c, sel)
    cnames = colnames(c, which)
    if all(x->isa(x, Symbol), cnames)
        tuplewrap = namedtuple(cnames...)
    else
        tuplewrap = tuple
    end
    tuplewrap((rows(c, w) for w in which)...)
end

"""
`columns(itr, which)`

Returns a vector or a tuple of vectors from the iterator.

"""
columns(t, which) = column(t, which)

function colnames(c, cols::Union{Tuple, AbstractArray})
    map(x->colname(c, x), cols)
end

colnames(c, cols::SpecialSelector) = colnames(c, lowerselection(c, cols))

function colname(c, col)
    if isa(col, Union{Int, Symbol})
        col == 0 && return 0
        i = colindex(c, col)
        return colnames(c)[i]
    elseif isa(col, Pair{<:Any, <:Any})
        return col[1]
    elseif isa(col, Tuple)
        #ns = map(x->colname(c, x), col)
        return 0
    elseif isa(col, SpecialSelector)
        return 0
    elseif isa(col, AbstractVector)
        return 0
    end
    error("column named $col not found")
end

"""
`rows(itr[, select::Selection])`

Select one or more fields from an iterable of rows as a vector of their values.

`select` specifies which fields to select. See [`Selection convention`](@ref select) for possible values. If unspecified, returns all columns.

`itr` can be `NDSparse`, `Columns` and `AbstractVector`, and their distributed counterparts.

# Examples

```jldoctest
julia> t = table([1,2],[3,4], names=[:x,:y])
Table with 2 rows, 2 columns:
x  y
────
1  3
2  4

julia> rows(t)
2-element IndexedTables.Columns{NamedTuples._NT_x_y{Int64,Int64},NamedTuples._NT_x_y{Array{Int64,1},Array{Int64,1}}}:
 (x = 1, y = 3)
 (x = 2, y = 4)

julia> rows(t, :x)
2-element Array{Int64,1}:
 1
 2

julia> rows(t, (:x,))
2-element IndexedTables.Columns{NamedTuples._NT_x{Int64},NamedTuples._NT_x{Array{Int64,1}}}:
 (x = 1)
 (x = 2)

julia> rows(t, (:y,:x=>-))
2-element IndexedTables.Columns{NamedTuples._NT_y_x{Int64,Int64},NamedTuples._NT_y_x{Array{Int64,1},Array{Int64,1}}}:
 (y = 3, x = -1)
 (y = 4, x = -2)
```
Note that vectors of tuples returned are `Columns` object and have columnar internal storage.
"""
function rows end

rows(x::AbstractVector) = x
function rows(cols::Tup)
    if nfields(cols) === 0
        error("Cannot construct rows with 0 columns")
    else
        Columns(cols)
    end
end

rows(t, which...) = rows(columns(t, which...))

_cols_tuple(xs::Columns) = columns(xs)
_cols_tuple(xs::AbstractArray) = (xs,)
concat_cols(xs, ys) = rows(concat_tup(_cols_tuple(xs), _cols_tuple(ys)))

## Mutable Columns Dictionary

mutable struct ColDict{T}
    pkey::Vector{Int}
    src::T
    names::Vector
    columns::Vector
    copy::Union{Void, Bool}
end

"""
    d = ColDict(t)

Create a mutable dictionary of columns in `t`.

To get the immutable iterator of the same type as `t`
call `d[]`
"""
function ColDict(t; copy=nothing)
    ColDict(Int[], t, convert(Array{Any}, Base.copy(colnames(t))), Any[columns(t)...], copy)
end

function Base.getindex(d::ColDict{<:Columns})
    Columns(d.columns...; names=d.names)
end

Base.getindex(d::ColDict, key) = rows(d[], key)
Base.getindex(d::ColDict, key::AbstractArray) = key

function Base.setindex!(d::ColDict, x, key::Union{Symbol, Int})
    k = _colindex(d.names, key, 0)
    col = d[x]
    if k == 0
        push!(d.names, key)
        push!(d.columns, col)
    elseif k in d.pkey
        # primary key column has been modified.
        # copy the table as this results in a shuffle
        if d.copy === nothing
            d.copy = true
        end
        d.columns[k] = col
    else
        d.columns[k] = col
    end
end

function Base.haskey(d::ColDict, key)
    _colindex(d.names, key, 0) != 0
end

function Base.insert!(d::ColDict, index, key, col)
    if haskey(d, key)
        error("Key $key already exists. Use dict[key] = col instead of inserting.")
    else
        insert!(d.names, index, key)
        insert!(d.columns, index, rows(d.src, col))
        for (i, pk) in enumerate(d.pkey)
            if pk >= index
                d.pkey[i] += 1 # moved right
            end
        end
    end
end

function insertafter!(d::ColDict, i, key, col)
    k = _colindex(d.names, i, 0)
    if k == 0
        error("$i not found. Cannot insert column after $i")
    end
    insert!(d, k+1, key, col)
end

function insertbefore!(d::ColDict, i, key, col)
    k = _colindex(d.names, i, 0)
    if k == 0
        error("$i not found. Cannot insert column after $i")
    end
    insert!(d, k, key, col)
end

function Base.pop!(d::ColDict, key=length(s.names))
    k = _colindex(d.names, key, 0)
    local col
    if k == 0
        error("Column $key not found")
    else
        col = d.columns[k]
        deleteat!(d.names, k)
        deleteat!(d.columns, k)
        idx = [pk[1] for pk in enumerate(d.pkey) if pk[2] == k]
        deleteat!(d.pkey, idx)
        for i in 1:length(d.pkey)
            if d.pkey[i] > k
                d.pkey[i] -= 1
            end
        end
        if !isempty(idx) && d.copy === nothing
            # set copy to true
            d.copy = true
        end
    end
    col
end

function rename!(d::ColDict, col, newname)
    k = _colindex(d.names, col, 0)
    if k == 0
        error("$col not found. Cannot rename it.")
    end
    d.names[k] = newname
end

function Base.push!(d::ColDict, key, x)
    push!(d.names, key)
    push!(d.columns, rows(d.src, x))
end

function _cols(expr)
    if expr.head == :call
        dict = :(dict = ColDict($(expr.args[2])))
        expr.args[2] = :dict
        quote
            let $dict
                $expr
                dict[]
            end
        end |> esc
    else
        error("This form of @cols is not implemented. Use `@cols f(t,args...)` where `t` is the collection.")
    end
end

macro cols(expr)
    _cols(expr)
end

# Modifying a columns

"""
`setcol(t::Table, col::Union{Symbol, Int}, x::Selection)`

Sets a `x` as the column identified by `col`. Returns a new table.

`setcol(t::Table, map::Pair...)`

Set many columns at a time.

# Examples:

```jldoctest setcol
julia> t = table([1,2], [3,4], names=[:x, :y])
Table with 2 rows, 2 columns:
x  y
────
1  3
2  4

julia> setcol(t, 2, [5,6])
Table with 2 rows, 2 columns:
x  y
────
1  5
2  6

```

`x` can be any selection that transforms existing columns.

```jldoctest setcol
julia> setcol(t, :x, :x => x->1/x)
Table with 2 rows, 2 columns:
x    y
──────
1.0  5
0.5  6

```

`setcol` will result in a re-sorted copy if a primary key column is replaced.

```jldoctest setcol
julia> t = table([0.01, 0.05], [1,2], [3,4], names=[:t, :x, :y], pkey=:t)
Table with 2 rows, 3 columns:
t     x  y
──────────
0.01  1  3
0.05  2  4

julia> t2 = setcol(t, :t, [0.1,0.05])
Table with 2 rows, 3 columns:
t     x  y
──────────
0.05  2  4
0.1   1  3

julia> t == t2
false

```
"""
setcol(t, col, x) = @cols setindex!(t, x, col)

"""
`pushcol(t, name, x)`

Push a column `x` to the end of the table. `name` is the name for the new column. Returns a new table.

# Example:

```jldoctest
julia> t = table([0.01, 0.05], [2,1], [3,4], names=[:t, :x, :y], pkey=:t)
Table with 2 rows, 3 columns:
t     x  y
──────────
0.01  2  3
0.05  1  4

julia> pushcol(t, :z, [1//2, 3//4])
Table with 2 rows, 4 columns:
t     x  y  z
────────────────
0.01  2  3  1//2
0.05  1  4  3//4

```
"""
pushcol(t, name, x) = @cols push!(t, name, x)

"""
`popcol(t, col)`

Remove the column `col` from the table. Returns a new table.

```jldoctest
julia> t = table([0.01, 0.05], [2,1], [3,4], names=[:t, :x, :y], pkey=:t)
Table with 2 rows, 3 columns:
t     x  y
──────────
0.01  2  3
0.05  1  4

julia> popcol(t, :x)
Table with 2 rows, 2 columns:
t     y
───────
0.01  3
0.05  4
```
"""
popcol(t, name) = @cols pop!(t, name)

"""
`insertcol(t, position::Integer, name, x)`

Insert a column `x` named `name` at `position`. Returns a new table.

```jldoctest
julia> t = table([0.01, 0.05], [2,1], [3,4], names=[:t, :x, :y], pkey=:t)
Table with 2 rows, 3 columns:
t     x  y
──────────
0.01  2  3
0.05  1  4

julia> insertcol(t, 2, :w, [0,1])
Table with 2 rows, 4 columns:
t     w  x  y
─────────────
0.01  0  2  3
0.05  1  1  4

```
"""
insertcol(t, i::Integer, name, x) = @cols insert!(t, i, name, x)

"""
`insertcolafter(t, after, name, col)`

Insert a column `col` named `name` after `after`. Returns a new table.

```jldoctest
julia> t = table([0.01, 0.05], [2,1], [3,4], names=[:t, :x, :y], pkey=:t)
Table with 2 rows, 3 columns:
t     x  y
──────────
0.01  2  3
0.05  1  4

julia> insertcolafter(t, :t, :w, [0,1])
Table with 2 rows, 4 columns:
t     w  x  y
─────────────
0.01  0  2  3
0.05  1  1  4
```
"""
insertcolafter(t, after, name, x) = @cols insertafter!(t, after, name, x)

"""
`insertcolbefore(t, before, name, col)`

Insert a column `col` named `name` before `before`. Returns a new table.

```jldoctest
julia> t = table([0.01, 0.05], [2,1], [3,4], names=[:t, :x, :y], pkey=:t)
Table with 2 rows, 3 columns:
t     x  y
──────────
0.01  2  3
0.05  1  4

julia> insertcolbefore(t, :x, :w, [0,1])
Table with 2 rows, 4 columns:
t     w  x  y
─────────────
0.01  0  2  3
0.05  1  1  4
```
"""
insertcolbefore(t, before, name, x) = @cols insertbefore!(t, before, name, x)

"""
`renamecol(t, col, newname)`

Set `newname` as the new name for column `col` in `t`. Returns a new table.

```jldoctest
julia> t = table([0.01, 0.05], [2,1], names=[:t, :x])
Table with 2 rows, 2 columns:
t     x
───────
0.01  2
0.05  1

julia> renamecol(t, :t, :time)
Table with 2 rows, 2 columns:
time  x
───────
0.01  2
0.05  1
```
"""
renamecol(t, name, newname) = @cols rename!(t, name, newname)

## Utilities for mapping and reduction with many functions / OnlineStats

using OnlineStats

@inline _apply(f::OnlineStat, g, x) = (fit!(g, x); g)
@inline _apply(f::Tup, y::Tup, x::Tup) = map(_apply, f, y, x)
@inline _apply(f, y, x) = f(y, x)
@inline _apply(f::Tup, x::Tup) = map(_apply, f, x)
@inline _apply(f, x) = f(x)

@inline init_first(f, x) = x
@inline init_first(f::OnlineStat, x) = (g=copy(f); fit!(g, x); g)
@inline init_first(f::Tup, x::Tup) = map(init_first, f, x)

# Initialize type of output, functions to apply, input and output vectors

function reduced_type(f, x, isvec, key = nothing)
    if key !== nothing
        _promote_op(f, eltype(key), typeof(x))
    elseif isvec
        _promote_op(f, typeof(x))
    else
        _promote_op((a,b)->_apply(f, init_first(f, a), b),
                    eltype(x), eltype(x))
    end
end

function init_inputs(f, x, gettype, isvec) # normal functions
    f, x, gettype(f, x, isvec)
end

nicename(f) = Symbol(f)
nicename(o::OnlineStat) = Symbol(typeof(o).name.name)

function mapped_type(f, x, isvec)
    _promote_op(f, eltype(x))
end

init_funcs(f, isvec) = init_funcs((f,), isvec)

function init_funcs(f::Tup, isvec)
    if isa(f, NamedTuple)
        return init_funcs((map(Pair, fieldnames(f), f)...), isvec)
    end

    funcmap = map(f) do g
        if isa(g, Pair)
            name = g[1]
            if isa(g[2], Pair)
                sel, fn = g[2]
            else
                sel = nothing
                fn = g[2]
            end
            (name, sel, fn)
        else
            (nicename(g), nothing, g)
        end
    end

    ns = map(x->x[1], funcmap)
    ss = map(x->x[2], funcmap)
    fs = map(map(x->x[3], funcmap)) do f
        f
    end

    namedtuple(ns...)(fs...), ss
end

function init_inputs(f::Tup, input, gettype, isvec)
    if isa(f, NamedTuple)
        return init_inputs((map(Pair, fieldnames(f), f)...), input, gettype, isvec)
    end
    fs, selectors = init_funcs(f, isvec)

    xs = map(s->s === nothing ? input : rows(input, s), selectors)

    output_eltypes = map((f,x) -> gettype(f, x, isvec), fs, xs)

    ns = fieldnames(fs)
    NT = namedtuple(ns...)

    # functions, input, output_eltype
    NT(fs...), rows(NT(xs...)), NT{output_eltypes...}
end
