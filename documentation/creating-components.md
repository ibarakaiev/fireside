# Creating a Fireside component

## Fireside config

In order to turn an existing Elixir project into a Fireside component, you
simply need to add a `fireside.exs` file in the root of your project,
with contents similar to the following:

```elixir
defmodule MyComponent.FiresideConfig do
  def config do
    [
      name: :my_component,
      version: 1,
      files: [
        required: [
          "lib/my_component/context.ex",
          "lib/my_component/context/**/*.{ex,exs}",
          "test/my_component/**/*_test.{ex,exs}"
        ],
        optional: [
          "lib/shopifex_web/endpoint.ex"
        ]
      ]
    ]
  end
end
```

Igniter will then import all files at the provided globs and replace
`MyComponent` with the name of your app (e.g. `MyApp`) and `:my_component`
with the Mix project name of your app (e.g. `:my_app`).

> ### Note {: .info}
> Replacing is done by comparing prefixes; that is, `MyComponentWeb` will
> become `MyAppWeb`. Similarly, `:my_component_web` will become
> `my_app_web`.

### Required files

Files marked as `required` will be installed if there are no existing
conflicting files with the same name. Fireside will track these files in
`config/fireside.exs` and they will be updated each time they are updated
in the remote.

### Optional files
Files marked as `optional` will be installed only if they don't already exist.
(This also means that they will only ever be installed once, even if their
remote implementation changes.)

For example, if you're working on a component that emits messages to PubSub
(but doesn't require receiving messages from it), you may add a simple
placeholder implementation like:

```elixir
defmodule MyComponentWeb.Endpoint do
  def broadcast(_, _, _), do: :ok
end
```

Then, if the component is being imported into a Phoenix project, the default
Phoenix `endpoint.ex` will remain used; otherwise, the optional placeholder
implementation will be used.

Fireside _does not_ track optional files in `config/fireside.exs`.

## Additional setup (optional)

Sometimes, simply importing files is not sufficient to fully install a
component. For instance, if the configuration in `config/config.exs` needs
to change for the component to work, you may define a `setup/1` method and
use [Igniter](https://hexdocs.pm/igniter) to add manual code generation
logic.

For example, if you are adding [Ash](https://hexdocs.pm/ash) resources, you may
need to add domains to `config :my_app, ash_domains: []` and generate
migrations. You can achieve this with the following `setup/1` function:

```elixir
def setup(igniter) do
  app_name = Igniter.Project.Application.app_name(igniter)

  igniter
  |> Igniter.Project.Config.configure(
    "config.exs",
    app_name,
    [:ash_domains],
    [MyComponent.Products],
    updater: fn zipper ->
      Igniter.Code.List.append_new_to_list(zipper, MyComponent.Products)
    end
  )
  |> Ash.Igniter.codegen("setup_products")
  |> Igniter.add_notice("Make sure to run `mix ash.migrate`.")
end
```

Note: `setup/1` needs to return an `%Igniter{}` as well.

## Versioning

Fireside supports component versioning. Sometimes, these version changes
require manual steps such as changing configuration, generating migrations, or
simply adding plain notices. In that case, optional `upgrade/3` hooks can be
defined. They look as follows:

```elixir
def upgrade(igniter, 1, 2) do
  # add component migration logic here
  igniter
  |> ...
end
```
