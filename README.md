# Fireside

Fireside is a small Elixir library that allows importing code components
(templates) into an existing Elixir project together with their dependencies.
It _also_ allows upgrading these components if they have a newer version
available.

## Installation

```elixir
def deps do
  [
    {:fireside, "~> 0.1", only: :dev, runtime: false}
  ]
end
```

## Use cases

- **_Embedded_ microservices**: using Fireside allows to split up a monolith into
  microservices while _still maintaining the monolith_. You get the benefits of
  both worlds:
  - Isolated, testable microservices and improved developer productivity in
    larger teams.
  - One distributed BEAM runtime.

  Typically, a monolith approach comes with slower reviews (in larger teams) and
  the microservices approach comes with additional complexity, the need for
  communication protocols, queues, etc. With Fireside and Elixir, you can
  develop individual microservices and embed them into your monolith
  with one command. You can even embed them in multiple monoliths.
- **Framework templates**: if you ever created a Phoenix project, you most
  likely created it with `mix phx.new ...`, which creates a brand new
  Elixir application. This comes with a major drawback: it requires, well, a
  _new_ Elixir project. If Phoenix's template was a Fireside component, it
  would've been possible to add it to an _existing_ Elixir app.
- **Portable business logic**: if you are a development agency, you can extract
  reusable code into individual Fireside components, reuse them in your
  projects, and update all your projects with one command.
- **Paid components**: if you run something like [Petal](https://petal.build/),
  you can make your components installable in one CLI command using Fireside.
  If you ever release a new version, they can be updated in one command as
  well.
- **Tutorials**: suppose you are writing a great coding tutorial such as
  [Small Development Kits](https://dashbit.co/blog/sdks-with-req-stripe) or
  [S3 with Tigris](https://fly.io/phoenix-files/what-if-s3-could-be-a-fast-globally-synced-key-value-database-that-s-tigris/).
  You can make the code available as a Fireside component, which means your
  readers can import it to an existing project with just one CLI command.

## Usage

To see supported Fireside tasks, refer to
[Mix Tasks](https://hexdocs.pm/fireside/doc/api-reference.html#mix-tasks).

## Upgrading code components with Fireside

Fireside supports two modes of installing a code component (template): locked
and unlocked. If you are installing a code component in the "unlocked" mode,
it will just install the code and forget about it. If you are installing it in
the "locked" mode (default), it will compute the hash of its AST, annotate each
generated file as "DO NOT EDIT", and record the hash in `config/fireside.exs`.
Later, when updating to a newer version, Fireside will know which files belong
to which component and whether they have been mistakenly modified.

## Example Fireside component

To see an example Fireside component, check out [Shopifex](https://github.com/ibarakaiev/shopifex),
a component that provides the backbone for an e-commerce online store.

