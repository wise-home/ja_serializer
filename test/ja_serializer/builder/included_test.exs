defmodule JaSerializer.Builder.IncludedTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  defmodule ArticleSerializer do
    use JaSerializer

    def type, do: "articles"
    attributes([:title])

    has_many(
      :comments,
      serializer: JaSerializer.Builder.IncludedTest.CommentSerializer,
      include: true
    )

    has_one(
      :author,
      serializer: JaSerializer.Builder.IncludedTest.PersonSerializer,
      include: true
    )

    has_many(
      :tags,
      serializer: JaSerializer.Builder.IncludedTest.TagSerializer
    )
  end

  defmodule OptionalIncludeArticleSerializer do
    use JaSerializer

    def type, do: "articles"
    attributes([:title])

    has_many(
      :comments,
      serializer: JaSerializer.Builder.IncludedTest.CommentSerializer,
      identifiers: :when_included
    )

    has_one(
      :author,
      serializer: JaSerializer.Builder.IncludedTest.PersonSerializer,
      identifiers: :when_included
    )

    has_many(
      :tags,
      serializer: JaSerializer.Builder.IncludedTest.TagSerializer,
      identifiers: :always
    )
  end

  defmodule PersonSerializer do
    use JaSerializer
    def type, do: "people"
    attributes([:first_name, :last_name])

    has_one(
      :publishing_agent,
      serializer: JaSerializer.Builder.IncludedTest.PersonSerializer,
      include: false
    )
  end

  defmodule TagSerializer do
    use JaSerializer
    def type, do: "tags"
    attributes([:tag])
  end

  defmodule CommentSerializer do
    use JaSerializer
    def type, do: "comments"
    location("/comments/:id")
    attributes([:body])

    has_one(
      :author,
      serializer: JaSerializer.Builder.IncludedTest.PersonSerializer,
      include: true
    )

    has_many(
      :comments,
      serializer: JaSerializer.Builder.IncludedTest.CommentSerializer,
      include: true
    )

    has_many(
      :tags,
      serializer: JaSerializer.Builder.IncludedTest.TagSerializer
    )
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:ja_serializer, :key_format)
    end)

    :ok
  end

  test "multiple levels of includes are respected" do
    p1 = %TestModel.Person{id: "p1", first_name: "p1"}
    p2 = %TestModel.Person{id: "p2", first_name: "p2"}
    c1 = %TestModel.Comment{id: "c1", body: "c1", author: p2}
    c2 = %TestModel.Comment{id: "c2", body: "c2", author: p1}

    a1 = %TestModel.Article{
      id: "a1",
      title: "a1",
      author: p1,
      comments: [c1, c2]
    }

    context = %{data: a1, conn: %{}, serializer: ArticleSerializer, opts: []}
    primary_resource = JaSerializer.Builder.ResourceObject.build(context)
    includes = JaSerializer.Builder.Included.build(context, primary_resource)

    ids = Enum.map(includes, & &1.id)
    assert "p1" in ids
    assert "p2" in ids
    assert "c1" in ids
    assert "c2" in ids

    assert [_, _, _, _] = includes

    # Formatted
    json = JaSerializer.format(ArticleSerializer, a1)
    assert %{} = json["data"]
    assert [_, _, _, _] = json["included"]
  end

  test "duplicate models are not included twice" do
    p1 = %TestModel.Person{id: "p1", first_name: "p1"}
    c1 = %TestModel.Comment{id: "c1", body: "c1", author: p1}
    c2 = %TestModel.Comment{id: "c2", body: "c2", author: p1}

    a1 = %TestModel.Article{
      id: "a1",
      title: "a1",
      author: p1,
      comments: [c1, c2]
    }

    context = %{data: a1, conn: %{}, serializer: ArticleSerializer, opts: []}
    primary_resource = JaSerializer.Builder.ResourceObject.build(context)
    includes = JaSerializer.Builder.Included.build(context, primary_resource)

    ids = Enum.map(includes, & &1.id)
    assert [_, _, _] = includes
    assert "p1" in ids
    assert "c1" in ids
    assert "c2" in ids

    # Formatted
    json = JaSerializer.format(ArticleSerializer, a1)
    assert %{} = json["data"]
    assert [_, _, _] = json["included"]
  end

  test "specifying a serializer as the `include` option logs warning but still works" do
    c1 = %TestModel.Comment{id: "c1", body: "c1"}
    a1 = %TestModel.Article{id: "a1", title: "a1", comments: [c1]}

    error_output =
      capture_io(:stderr, fn ->
        defmodule DeprecatedArticleSerializer do
          use JaSerializer

          def type, do: "articles"
          attributes([:title])

          has_many(
            :comments,
            include: JaSerializer.Builder.IncludedTest.CommentSerializer
          )
        end

        context = %{
          data: a1,
          conn: %{},
          serializer: DeprecatedArticleSerializer,
          opts: []
        }

        primary_resource = JaSerializer.Builder.ResourceObject.build(context)

        includes =
          JaSerializer.Builder.Included.build(context, primary_resource)

        ids = Enum.map(includes, & &1.id)
        assert [_] = includes
        assert "c1" in ids

        # Formatted
        json = JaSerializer.format(DeprecatedArticleSerializer, a1)
        assert %{} = json["data"]
        assert [_] = json["included"]
      end)

    assert error_output =~
             ~r/Specifying a non-boolean as the `include` option is deprecated/
  end

  # Optional includes
  test "only specified relationships serialized when 'include' option defined" do
    p1 = %TestModel.Person{id: "p1", first_name: "p1"}
    p2 = %TestModel.Person{id: "p2", first_name: "p2"}
    c1 = %TestModel.Comment{id: "c1", body: "c1", author: p2}
    c2 = %TestModel.Comment{id: "c2", body: "c2", author: p1}
    t1 = %TestModel.Tag{id: "t1", tag: "tag1"}

    a1 = %TestModel.Article{
      id: "a1",
      title: "a1",
      author: p1,
      comments: [c1, c2],
      tags: [t1]
    }

    opts = %{include: [author: []]}

    context = %{
      data: a1,
      conn: %{},
      serializer: OptionalIncludeArticleSerializer,
      opts: opts
    }

    primary_resource = JaSerializer.Builder.ResourceObject.build(context)
    includes = JaSerializer.Builder.Included.build(context, primary_resource)

    ids = Enum.map(includes, & &1.id)
    assert [_] = ids
    assert "p1" in ids

    # Formatted
    json =
      JaSerializer.format(
        OptionalIncludeArticleSerializer,
        a1,
        %{},
        include: "author"
      )

    assert %{} = json["data"]
    assert [_] = json["included"]

    assert [%{"id" => "t1", "type" => "tags"}] ==
             json["data"]["relationships"]["tags"]["data"]

    refute json["data"]["relationships"]["comments"]["data"]
  end

  test "2nd level includes are serialized correctly" do
    p1 = %TestModel.Person{id: "p1", first_name: "p1"}
    p2 = %TestModel.Person{id: "p2", first_name: "p2"}
    c1 = %TestModel.Comment{id: "c1", body: "c1", author: p2}
    c2 = %TestModel.Comment{id: "c2", body: "c2", author: p1}

    a1 = %TestModel.Article{
      id: "a1",
      title: "a1",
      author: p1,
      comments: [c1, c2]
    }

    opts = %{include: [author: [], comments: [author: []]]}

    context = %{
      data: a1,
      conn: %{},
      serializer: OptionalIncludeArticleSerializer,
      opts: opts
    }

    primary_resource = JaSerializer.Builder.ResourceObject.build(context)
    includes = JaSerializer.Builder.Included.build(context, primary_resource)

    ids = Enum.map(includes, & &1.id)
    assert [_, _, _, _] = ids
    assert "p1" in ids
    assert "p2" in ids
    assert "c1" in ids
    assert "c2" in ids

    # Formatted
    json =
      JaSerializer.format(
        OptionalIncludeArticleSerializer,
        a1,
        %{},
        include: "author,comments.author"
      )

    assert %{} = json["data"]
    assert [_, _, _, _] = json["included"]
  end

  test "sibling includes are serialized correctly" do
    p1 = %TestModel.Person{id: "p1", first_name: "p1"}
    t1 = %TestModel.Tag{id: "t1", tag: "t1"}
    t2 = %TestModel.Tag{id: "t2", tag: "t2"}
    c1 = %TestModel.Comment{id: "c1", body: "c1", author: p1, tags: [t2]}

    a1 = %TestModel.Article{
      id: "a1",
      title: "a1",
      author: p1,
      comments: [c1],
      tags: [t1]
    }

    opts = %{include: [tags: [], comments: [author: [], tags: []]]}

    context = %{
      data: a1,
      conn: %{},
      serializer: OptionalIncludeArticleSerializer,
      opts: opts
    }

    primary_resource = JaSerializer.Builder.ResourceObject.build(context)
    includes = JaSerializer.Builder.Included.build(context, primary_resource)

    ids = Enum.map(includes, & &1.id)
    assert [_, _, _, _] = ids
    assert "p1" in ids
    assert "c1" in ids
    assert "t1" in ids
    assert "t2" in ids

    # Formatted
    json =
      JaSerializer.format(
        OptionalIncludeArticleSerializer,
        a1,
        %{},
        include: "tags,comments.author,comments.tags"
      )

    assert %{} = json["data"]

    included = json["included"]
    assert [_, _, _, _] = included

    resource_by_id_by_type =
      Enum.reduce(
        included,
        %{},
        fn resource = %{"id" => id, "type" => type}, resource_by_id_by_type ->
          resource_by_id_by_type
          |> Map.put_new(type, %{})
          |> put_in([type, id], resource)
        end
      )

    c1_resource = resource_by_id_by_type["comments"]["c1"]
    assert %{"data" => c1_tags_data} = c1_resource["relationships"]["tags"]
    assert c1_tags_data == [%{"type" => "tags", "id" => t2.id}]
  end

  test "duplicated sibling includes are serialized correctly" do
    publishing_agent1 = %TestModel.Person{id: "pa1", first_name: "pa1 name"}
    publishing_agent2 = %TestModel.Person{id: "pa2", first_name: "pa2 name"}

    author1 = %TestModel.Person{
      id: "au1",
      first_name: "author1 name",
      publishing_agent: publishing_agent1
    }

    author2 = %TestModel.Person{
      id: "au2",
      first_name: "author2 name",
      publishing_agent: publishing_agent2
    }

    comment1 = %TestModel.Comment{
      id: "c1",
      body: "body 1",
      author: author1
    }

    comment2 = %TestModel.Comment{
      id: "c2",
      body: "body 2",
      author: author2
    }

    article = %TestModel.Article{
      id: "ar1",
      title: "ar title",
      comments: [comment1, comment2],
      author: author1
    }

    opts = %{include: [author: [], comments: [author: [publishing_agent: []]]]}

    context = %{
      data: article,
      conn: %{},
      serializer: OptionalIncludeArticleSerializer,
      opts: opts
    }

    primary_resource = JaSerializer.Builder.ResourceObject.build(context)
    includes = JaSerializer.Builder.Included.build(context, primary_resource)

    ids = Enum.map(includes, & &1.id)

    assert [_, _, _, _, _, _] = ids
    assert "pa1" in ids
    assert "pa2" in ids
    assert "au1" in ids
    assert "au2" in ids
    assert "c1" in ids
    assert "c2" in ids

    json =
      JaSerializer.format(
        OptionalIncludeArticleSerializer,
        article,
        %{},
        include: "author,comments.author.publishing-agent"
      )

    assert %{} = json["data"]

    assert json["data"]["relationships"]["author"]["data"]["id"] == "au1"

    article_comments = json["data"]["relationships"]["comments"]["data"]
    assert Enum.any?(article_comments, &(&1["id"] == "c1"))
    assert Enum.any?(article_comments, &(&1["id"] == "c2"))

    included = json["included"]
    assert [_, _, _, _, _, _] = included
  end

  test "sparse fieldset returns only specified fields" do
    p1 = %TestModel.Person{id: "p1", first_name: "p1", last_name: "p1"}
    a1 = %TestModel.Article{id: "a1", title: "a1", body: "a1", author: p1}

    fields = %{"articles" => "title", "people" => "first_name"}
    opts = [fields: fields]
    context = %{data: a1, conn: %{}, serializer: ArticleSerializer, opts: opts}
    primary_resource = JaSerializer.Builder.ResourceObject.build(context)
    includes = JaSerializer.Builder.Included.build(context, primary_resource)

    assert %{id: "a1", attributes: attributes} = primary_resource
    assert [_] = attributes

    assert [person] = includes
    assert [_] = person.attributes

    # Formatted
    json = JaSerializer.format(ArticleSerializer, a1, %{}, fields: fields)
    assert %{"attributes" => formatted_attrs} = json["data"]
    article_attrs = Map.keys(formatted_attrs)
    assert [_] = article_attrs
    assert "title" in article_attrs
    refute "body" in article_attrs

    assert [formatted_person] = json["included"]
    person_attrs = Map.keys(formatted_person["attributes"])
    assert [_] = person_attrs
    assert "first-name" in person_attrs
    refute "last-name" in person_attrs
  end

  test "sparse fieldset restricts on a per-type basis only" do
    p1 = %TestModel.Person{id: "p1", first_name: "p1", last_name: "p1"}
    a1 = %TestModel.Article{id: "a1", title: "a1", body: "a1", author: p1}

    fields = %{"articles" => "title"}
    opts = [fields: fields]
    context = %{data: a1, conn: %{}, serializer: ArticleSerializer, opts: opts}
    primary_resource = JaSerializer.Builder.ResourceObject.build(context)
    includes = JaSerializer.Builder.Included.build(context, primary_resource)

    assert [person] = includes
    assert [_, _] = person.attributes

    # Formatted
    json = JaSerializer.format(ArticleSerializer, a1, %{}, fields: fields)
    assert [formatted_person] = json["included"]
    person_attrs = Map.keys(formatted_person["attributes"])
    assert [_, _] = person_attrs
    assert "first-name" in person_attrs
    assert "last-name" in person_attrs
  end

  test "multi-word relationship path keys are formatted correctly" do
    p1 = %TestModel.Person{id: "p1", first_name: "p1"}
    p2 = %TestModel.Person{id: "p2", first_name: "p2", publishing_agent: p1}
    c1 = %TestModel.Comment{id: "c1", body: "c1", author: p2}
    a1 = %TestModel.Article{id: "a1", title: "a1", author: p2, comments: [c1]}

    json =
      JaSerializer.format(
        ArticleSerializer,
        a1,
        %{},
        include: "author.publishing-agent"
      )

    assert includes = json["included"]
    ids = Enum.map(includes, &Map.get(&1, "id"))
    assert "p1" in ids

    Application.put_env(:ja_serializer, :key_format, :dasherized)

    json =
      JaSerializer.format(
        ArticleSerializer,
        a1,
        %{},
        include: "author.publishing-agent"
      )

    ids = Enum.map(json["included"], &Map.get(&1, "id"))
    assert "p1" in ids

    Application.put_env(:ja_serializer, :key_format, :underscored)

    json =
      JaSerializer.format(
        ArticleSerializer,
        a1,
        %{},
        include: "author.publishing_agent"
      )

    ids = Enum.map(json["included"], &Map.get(&1, "id"))

    assert "p1" in ids

    Application.put_env(
      :ja_serializer,
      :key_format,
      {:custom, String, :capitalize, :downcase}
    )

    json =
      JaSerializer.format(
        ArticleSerializer,
        a1,
        %{},
        include: "Author.Publishing_agent"
      )

    ids = Enum.map(json["included"], &Map.get(&1, "id"))
    assert "p1" in ids
  end
end
