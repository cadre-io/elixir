defmodule Mix.Version do
  @moduledoc %B"""
  This module provides functions for parsing and matching
  versions with requirements.

  A version is a string or a `Mix.Version.Schema` generated
  after parsing via `Mix.Version.parse/1`. A requirement is
  a string that follows a specific format.

  `Mix.Version` parsing and requirements follows
  [SemVer 2.0 schema](http://semver.org/) and you will get
  the most of Mix' version system by following it. In order
  to support integration with projects that may
  follow different versioning schemas, Elixir won't choke
  on unknown versions, however you won't be able to use
  Mix requirements with such unformatted versions.

  ## Versions

  In a nutshell, a version is given by three numbers:

      MAJOR.MINOR.PATCH

  Pre-releases are supported by appending `-[0-9A-Za-z-\.]`:

      "1.0.0-alpha3"

  Build information can be added by appending `+[0-9A-Za-z-\.]`:

      "1.0.0-alpha3+20130417140000"

  ## Requirements

  Requirements allow you to specify which versions of a given
  dependency you are willing to work against. It supports common
  operators like `>=`, `<=`, `>`, `==` and friends that would
  work as one would expect:

      # Only version 2.0.0
      "== 2.0.0"

      # Anything later than 2.0.0
      "> 2.0.0"

  Requirements also support `and` and `or` for complex conditions:

      # 2.0.0 and later until 2.1.0
      ">= 2.0.0 and < 2.1.0"

  Since the example above is such a common requirement, it can
  be expressed as:

      "~> 2.0.0"

  """

  @type t :: String.t | Mix.Version.Schema.t
  @type requirement :: String.t | Mix.Version.Requirement.t

  @type matchable :: { major :: String.t | non_neg_integer,
                       minor :: non_neg_integer | nil,
                       patch :: non_neg_integer | nil,
                       pre   :: { String.t, non_neg_integer } | nil }

   import Kernel, except: [match?: 2]

   defrecord Schema, major: 0, minor: 0, patch: 0, build: nil, source: nil
   defrecord Requirement, source: nil, matchspec: nil

  defexception InvalidRequirement, reason: :invalid_requirement do
    def message(InvalidRequirement[reason: reason]) when is_binary(reason) do
      { first, rest } = String.next_grapheme(reason)
      String.downcase(first) <> rest
    end

    def message(InvalidRequirement[]) do
      "invalid version specification"
    end
  end

  @doc """
  Checks if the given version matches the specification.
  """
  @spec match?(t, requirement) :: boolean
  def match?(version, requirement) when is_binary(requirement) do
    case Mix.Version.Parser.parse_requirement(requirement) do
      { :ok, req } ->
        match?(version, req)
      { :error, reason } ->
        raise InvalidRequirement, reason: reason
    end
  end

  def match?(version, requirement) when is_binary(version) do
    match?(parse(version), requirement)
  end

  def match?(Schema[] = version, Requirement[matchspec: spec]) do
    case :ets.test_ms(to_matchable(version), spec) do
      { :ok, result } ->
        result != false
      { :error, reason } ->
        raise InvalidRequirement, reason: reason
    end
  end

  @doc """
  Checks if a version string is compatible with [semver](http://semver.org/).

  ## Examples

      iex> Mix.Version.valid?("1")
      true
      iex> Mix.Version.valid?("1.0")
      true
      iex> Mix.Version.valid?("1.0.0")
      true
      iex> Mix.Version.valid?("1.0.0+alpha1")
      true
      iex> Mix.Version.valid?("1.0.0-alpha1")
      true
      iex> Mix.Version.valid?("1.0.3.4")
      false

  """
  @spec valid?(String.t | Schema.t) :: boolean
  def valid?(string) when is_binary(string) do
    Mix.Version.Parser.valid_version?(string)
  end

  def valid?(Mix.Version.Schema[major: nil]), do: false
  def valid?(Mix.Version.Schema[]),           do: true

  @doc """
  Parse a version into a matchable value.

  ## Examples

      iex> Mix.Version.parse("1")
      1
      iex> Mix.Version.parse("1.0")
      1.0
      iex> Mix.Version.parse("1.0.0")
      1.0.0
      iex> Mix.Version.parse("1.0.0+alpha1")
      1.0.0-alpha1
      iex> Mix.Version.parse("1.0.0-alpha1")
      1.0.0-alpha1
      iex> Mix.Version.parse("1.0.3.4")
      1.0.3.4

  """
  @spec parse(String.t) :: { :ok, Schema.t } | { :error, term }
  def parse(string) when is_binary(string) do
    case Mix.Version.Parser.parse_version(string) do
      { :ok, matchable } -> from_matchable(matchable)
      { :error, _ } -> Mix.Version.Schema[source: string]
    end
  end

  @doc """
  Get the matchable representation.

  ## Examples

      iex> Mix.Version.to_matchable("1")
      {1,0,0,nil}
      iex> Mix.Version.to_matchable("1.0")
      {1,0,0,nil}
      iex> Mix.Version.to_matchable("1.0.0")
      {1,0,0,nil}
      iex> Mix.Version.to_matchable("1.0.0+alpha1")
      {1,0,0,{"alpha",1}}
      iex> Mix.Version.to_matchable("1.0.0-alpha10")
      {1,0,0,{"alpha",10}}
      iex> Mix.Version.to_matchable("1.0.3.4")
      {"1.0.3.4",nil,nil,nil}

  """
  @spec to_matchable(String.t | Schema.t) :: Mix.Version.matchable
  def to_matchable(Schema[major: nil, source: source]) do
    { source, nil, nil, nil }
  end

  def to_matchable(Mix.Version.Schema[major: major, minor: minor, patch: patch, build: nil]) do
    { major, minor, patch, nil }
  end

  def to_matchable(Mix.Version.Schema[major: major, minor: minor, patch: patch, build: build]) do
    build = case Regex.run %r/^(.*?)(\d+)?$/, build do
      [_, build] ->
        { build, 0 }

      [_, build, number] ->
        { build, binary_to_integer(number) }
    end

    { major, minor, patch, build }
  end

  def to_matchable(string) do
    to_matchable(parse(string))
  end

  @doc """
  Convert a matchable to a `Mix.Version`.
  """
  @spec from_matchable(Mix.Version.matchable) :: Schema.t
  def from_matchable({ source, nil, nil, nil }) when is_binary(source) do
    Mix.Version.Schema[source: source]
  end

  def from_matchable({ major, minor, patch, build }) do
    source = "#{major}"

    if minor do
      source = "#{source}.#{minor}"

      if patch do
        source = "#{source}.#{patch}"

        if build do
          build  = "#{elem build, 0}#{elem build, 1}"
          source = "#{source}-#{build}"
        end
      end
    end

    Mix.Version.Schema[major: major, minor: minor, patch: patch, build: build, source: source]
  end

  defmodule Parser.DSL do
    @moduledoc false

    defmacro deflexer(match, do: body) when is_binary(match) do
      quote do
        def lexer(unquote(match) <> rest, acc) do
          lexer(rest, [unquote(body) | acc])
        end
      end
    end

    defmacro deflexer(acc, do: body) do
      quote do
        def lexer("", unquote(acc)) do
          unquote(body)
        end
      end
    end

    defmacro deflexer(char, acc, do: body) do
      quote do
        def lexer(<< unquote(char) :: utf8, rest :: binary >>, unquote(acc)) do
          unquote(char) = << unquote(char) :: utf8 >>

          lexer(rest, unquote(body))
        end
      end
    end
  end

  defmodule Parser do
    @moduledoc false
    import Parser.DSL

    deflexer ">=",    do: :'>='
    deflexer "<=",    do: :'<='
    deflexer "~>",    do: :'~>'
    deflexer ">",     do: :'>'
    deflexer "<",     do: :'<'
    deflexer "==",    do: :'=='
    deflexer "!=",    do: :'!='
    deflexer "!",     do: :'!='
    deflexer " or ",  do: :'||'
    deflexer " and ", do: :'&&'
    deflexer " ",     do: :' '

    deflexer x, [] do
      [x, :'==']
    end

    deflexer x, [h | acc] do
      cond do
        is_binary h ->
          [h <> x | acc]

        h in [:'||', :'&&'] ->
          [x, :'==', h | acc]

        true ->
          [x, h | acc]
      end
    end

    deflexer acc do
      Enum.filter(Enum.reverse(acc), &1 != :' ')
    end

    @version_regex %r/^(\d+)(?:\.(\d+)(?:\.(\d+))?)?(?:[\-+]([^\s]+))?$/

    @spec parse_requirement(String.t) :: { :ok, Mix.Version.Requirement.t } | { :error, binary | atom }
    def parse_requirement(source) do
      lexed = lexer(source, [])

      if valid_requirement?(lexed) do
        spec = to_matchspec(lexed)

        case :ets.test_ms({}, spec) do
          { :ok, _ } ->
            { :ok, Requirement[source: source, matchspec: spec] }

          { :error, [error: reason] } ->
            { :error, to_binary(reason) }
        end
      else
        { :error, :invalid_requirement }
      end
    end

    @spec parse_version(String.t) :: { :ok, Mix.Version.matchable } | { :error, :invalid_version }
    def parse_version(string) when is_binary(string) do
      if valid_version?(string) do
        destructure [_, major, minor, patch, build], Regex.run(@version_regex, string)

        major = binary_to_integer(major)
        minor = binary_to_integer(minor || "0")
        patch = binary_to_integer(patch || "0")
        build = build && parse_build(build)

        { :ok, { major, minor, patch, build } }
      else
        { :error, :invalid_version }
      end
    end

    defp parse_build(build) do
      case Regex.run(%r/^(.*?)(\d+)?$/, build) do
        [_, build] ->
          { build, 0 }

        [_, build, number] ->
          { build, binary_to_integer(number) }
      end
    end

    @spec valid_requirement?(list) :: boolean
    def valid_requirement?([]) do
      false
    end

    def valid_requirement?([a | next]) do
      valid_requirement?(a, next)
    end

    # it must finish with a version
    defp valid_requirement?(a, []) when is_binary(a) do
      true
    end

    # version version
    defp valid_requirement?(a, [b | _]) when is_binary(a) and is_binary(b) do
      false
    end

    # or <op> | and <op>
    defp valid_requirement?(a, [b | next]) when is_atom(a) and is_atom(b) and a in [:'||', :'&&'] do
      valid_requirement?(b, next)
    end

    # <version> or | <version> and
    defp valid_requirement?(a, [b | next]) when is_binary(a) and is_atom(b) and b in [:'||', :'&&'] do
      valid_requirement?(b, next)
    end

    # or <version> | and <version>
    defp valid_requirement?(a, [b | next]) when is_atom(a) and is_binary(b) and a in [:'||', :'&&'] do
      valid_requirement?(b, next)
    end

    # <op> <version>; also checks operators work on valid versions
    defp valid_requirement?(a, [b | next]) when is_atom(a) and is_binary(b) do
      if valid_version?(b) do
        valid_requirement?(b, next)
      else
        if a in [:'==', :'!='] and Regex.match? %r/^\w/, b do
          valid_requirement?(b, next)
        else
          false
        end
      end
    end

    defp valid_requirement?(_, _) do
      false
    end

    @spec valid_version?(String.t) :: boolean
    def valid_version?(string) do
      Regex.match? %r/^\d+(\.\d+(\.\d+)?)?([\-+][^\s]+)?$/, string
    end

    defp approximate(version) do
      Mix.Version.from_matchable(case Regex.run(@version_regex, version) do
        [_, major] ->
          { binary_to_integer(major) + 1, 0, 0, nil }

        [_, major, _] ->
          { binary_to_integer(major) + 1, 0, 0, nil }

        [_, major, minor, _] ->
          { binary_to_integer(major), binary_to_integer(minor) + 1, 0, nil }

        [_, major, minor, patch, _] ->
         { binary_to_integer(major), binary_to_integer(minor), binary_to_integer(patch) + 1, nil }
      end)
    end

    defp to_matchspec(lexed) do
      first = to_condition(lexed)
      rest  = Enum.drop(lexed, 2)

      [{{ :'$1', :'$2', :'$3', :'$4' }, [to_condition(first, rest)], [:'$_'] }]
    end

    defp to_condition([:'==', version | _]) do
      version = Mix.Version.to_matchable(version)

      { :'==', :'$_', { :const, version } }
    end

    defp to_condition([:'!=', version | _]) do
      version = Mix.Version.to_matchable(version)

      { :'/=', :'$_', { :const, version } }
    end

    defp to_condition([:'>', version | _]) do
      version = Mix.Version.to_matchable(version)

      { :andalso, { :not, { :is_binary, :'$1' } },
                  { :'>', :'$_', { :const, version } } }
    end

    defp to_condition([:'>=', version | _]) do
      version = Mix.Version.to_matchable(version)

      { :andalso, { :not, { :is_binary, :'$1' } },
                  { :'>=', :'$_', { :const, version } } }
    end

    defp to_condition([:'<', version | _]) do
      version = Mix.Version.to_matchable(version)

      { :andalso, { :not, { :is_binary, :'$1' } },
                  { :'<', :'$_', { :const, version } } }
    end

    defp to_condition([:'<=', version | _]) do
      version = Mix.Version.to_matchable(version)

      { :andalso, { :not, { :is_binary, :'$1' } },
                  { :'=<', :'$_', { :const, version } } }
    end

    defp to_condition([:'~>', version | _]) do
      from = Mix.Version.parse(version)
      to   = approximate(version)

      { :andalso, to_condition([:'>=', to_binary(from)]),
                  to_condition([:'<', to_binary(to)]) }
    end

    defp to_condition(current, []) do
      current
    end

    defp to_condition(current, [:'&&', operator, version | rest]) do
      to_condition({ :andalso, current, to_condition([operator, version]) }, rest)
    end

    defp to_condition(current, [:'||', operator, version | rest]) do
      to_condition({ :orelse, current, to_condition([operator, version]) }, rest)
    end
  end
end

defimpl Binary.Chars, for: Mix.Version.Schema do
  def to_binary(Mix.Version.Schema[source: source]) do
    source
  end
end

defimpl Binary.Inspect, for: Mix.Version.Schema do
  def inspect(self, _opts) do
    "#Mix.Version.Schema<" <> to_binary(self) <> ">"
  end
end

defimpl Binary.Chars, for: Mix.Version.Requirement do
  def to_binary({ _, source, _ }) do
    source
  end
end

defimpl Binary.Inspect, for: Mix.Version.Requirement do
  def inspect({ _, source, _ }, _opts) do
    "#Mix.Version.Requirement<" <> source <> ">"
  end
end
