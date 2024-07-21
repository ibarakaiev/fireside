# Fireside

Fireside is an Elixir library to install and maintain
self-contained application logic in your existing Elixir application with smart
code generation and Abstract Syntax Tree (AST) hashing.
Since the project is still in its early stages, its core functionality may
change unexpectedly. It uses [Igniter](https://hexdocs.pm/igniter) under
the hood to orchestrate code generation and modifications, which means that
it's possible to hook into it and add advanced generation steps such as
adding configuration to `config/config.exs`, adding a new child to the
application supervision tree, etc. Igniter itself uses
[`Sourceror.Zipper`](https://hexdocs.pm/sourceror/zippers.html),
so it is possible to do anything that Elixir's metaprogramming tools support,
but is probably unnecessary in most cases.

## Installation

```elixir
def deps do
  [
    {:fireside, "~> 0.0.1", only: :dev, runtime: false}
  ]
end
```

## What is a Fireside component?

A Fireside component is a self-contained piece of application logic
with a `fireside.exs` definition in its root. To create a Fireside component,
create a new Mix project with `mix new my_app --sup` and define your
application logic, i.e. core functionality and tests. Then, for example, if
your Fireside component adds a Products context, you may have the following
`fireside.exs` definition:

```elixir
defmodule MyApp.FiresideComponent do
  def config do
    %{
      lib: [
        "lib/my_app/products.ex",
        "lib/my_app/products/**/*.{ex,exs}"
      ],
      overwritable: ["lib/my_app/products/definitions.ex"],
      tests: [
        "test/my_app/**/*_test.{ex,exs}"
      ],
      test_supports: [
        "test/support/my_app/products_factory.ex"
      ]
    }
  end

  def setup(igniter) do
    # Add custom Igniter logic here, if necessary. It will be run immediately
    # after the files above are imported.
    igniter
  end
end
```

Now, it is possible to "install" this application into an existing Elixir
project with Fireside. The Fireside installer will take the following steps:

1. Look at `mix.exs` of the Fireside component and install all its dependencies
   as well as their Igniter installers. What this means is that, for example, if
   you are adding a Fireside component that uses [`Ash`](https://hexdocs.pm/ash)
   and [`AshPostgres`](https://hexdocs.pm/ash_postgres), their individual Igniter
   installers will be run, setting up everything along the way, such as the
   `Repo` module, required `config.exs` configuration, testing utilities, etc.
2. Import the source code from the paths in `MyApp.FiresideComponent.config/0`.
3. Run `MyApp.FiresideComponent.setup/1` for optional custom code modification.
4. Replace `MyApp` across the entire project with the prefix of your
   application.
5. Calculate the hash of each imported file (except the files listed as
   `overwritable`) and add it to its top, with a note that the file should not
   be changed manually.

At this point, the component should become a native part of the existing Elixir
application. If its version is updated remotely, Fireside will be able to
replace all relevant parts as long as the hashes of their AST do not differ
from their originals by running `fireside.update my_app`. If at any point the
component is no longer necessary, it can be removed with
`mix fireside.delete my_app`. If it is no longer sufficient
and needs to be extended/customized, it should be unlocked with
`mix fireside.unlock my_app` and all the files will become as if they were
never a Fireside component to begin with. If they are modified without
unlocking, Fireside will no longer be able to update them in the future,
and the generated files will contain a no-longer-useful notice that they should
not be modified.

### Example application

To see an example Fireside component, check out [Shopifex](https://github.com/ibarakaiev/shopifex),
a component that provides the backbone for an e-commerce online store.
If you want to test it out, create a new Mix project with
`mix new fireside_playground --sup`, clone Shopifex alongside it (in the same
parent directory), add `{:fireside, "~> 0.0.1"}` to `mix.exs` of
`FiresidePlayground` and then run
`mix fireside.install shopifex@path:../shopifex`.

## Tasks

### Currently supported tasks

- **`fireside.install {app_name}@path:..`**: installs an existing
  Fireside component under specified path.
- **`fireside.update {app_name}`**: updates an installed Fireside component
  to reflect all changes upstream.

### Planned tasks

- **`fireside.init`**: creates a `fireside.exs` in the root of the project.
  Will potentially include smart logic to guess its contents as well. This
  should be run only when developing a component.
- **`fireside.install {app_name}@github:..`** or **`fireside.install {app_name}@git:..`**:
  installs a Fireside component from a Git reference or from Github.
- **`fireside.install {app_name}@{version}`**: installs a Fireside component
  from the Fireside directory (TBD).
- **`fireside.unlock {app_name}`**: removes the lock from the provided
  component. Specifically, it will remove all hash information from the
  associated files and from `config/fireside.exs`. Once unlocked, a component
  becomes a regular part of the source code and Fireside will no longer be able
  to identify, track, and update it.
- **`fireside.install .. --unlocked`**: same as **`fireside.install`** but
  without locking the component. This can be useful if there are no plans to
  fetch changes from the upstream.
- **`fireside.delete {app_name}`**: completely removes the installed component
  from the project. Note: installed dependencies will remain in `mix.exs` and
  will need to be manually removed.

## Future direction

If this project proves to be useful to people other than myself, I might
create a centralized directory for Fireside components, similar to Hex,
where individual developers can publish and maintain their components. This
would hopefully create a helpful ecosystem of building blocks which other
developers can use to rapidly iterate their app with. In principle, these
components could be monetized as well.

## Why does Fireside exist?

There are certain application logic components that can (and maybe should)
be centralized and yet don't necessarily make sense to be a library
(i.e. if they depend on a database). Typically, they become a SaaS, either
self-hosted or paid for as a service, and require setting up communication
channels, adding unnecessary complexity.

Fireside hopes to provide an alternative by making it as easy as possible to
reuse application logic by _embedding_ it within your Elixir monolith and still
have all the benefits like version upgrades without additional engineering
overhead.

Fireside's implementation in Elixir is possible thanks to
[@ZachDaniel](https://github.com/zachdaniel)'s ongoing work on
[Igniter](https://hexdocs.pm/igniter), which powers most of Fireside, allowing
for smart, composable code generation and modification.

## Why does Fireside not exist in other languages?

Elixir/Phoenix/OTP is one of the few standardized ecosystems with common
conventions that allows creating an arbitrarily large distributed monolith with
a solid foundation
([a slide from Sasa Juric's talk](https://www.reddit.com/r/elixir/comments/gpdlp4/the_more_i_learn_about_elixir_the_more_i_realize/)
comes to mind). This allows writing code that can easily be reused across teams
and companies (compare this to the JavaScript or Python ecosystem with a
million different options to just install a package...).

Additionally, Elixir is an immutable language that supports metaprogramming.
In its closest spiritual relative and its ecosystem, Ruby and Ruby on Rails,
Fireside would probably not be possible due to mutability concerns and lack of
metaprogramming.
