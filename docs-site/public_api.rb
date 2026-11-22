# frozen_string_literal: true

require 'rbs'
require 'stringio'

module PublicApi
  extend self

  Entry = Data.define(:name, :method_names)

  CONSTANT = /\bRiffer::Rig(?:::[A-Z_]\w*)*/
  METHOD = [RBS::AST::Members::MethodDefinition, RBS::AST::Members::Attribute].freeze
  MIXIN = RBS::AST::Members::Mixin

  INTRO = <<~MARKDOWN
    # Public API

    riffer-rig's public API is exactly what this page lists: each constant below, and the methods shown under it. Anything not listed is internal, even when Ruby lets you call it or a signature here names it, and may change or disappear in any release.

    While riffer-rig is 0.x, a change to anything listed ships in:

    | Change          | Release                                                                                                                                                                      |
    | --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
    | Breaking change | A minor release, where possible after a release that deprecates it, with its upgrade steps in the [changelog](https://github.com/bottrall/riffer-rig/blob/main/CHANGELOG.md) |
    | New feature     | A minor release                                                                                                                                                              |
    | Bug fix         | A patch release                                                                                                                                                              |

    The signatures are [RBS](https://github.com/ruby/rbs).
  MARKDOWN

  def entries(list)
    list.map { |name, method_names| Entry.new(name: name, method_names: method_names) }
  end

  def environment(dirs)
    loader = RBS::EnvironmentLoader.new(core_root: nil)
    dirs.each { |dir| loader.add(path: Pathname(dir)) }
    RBS::Environment.from_loader(loader).resolve_type_names
  end

  def errors(entries, env)
    entries.flat_map { |entry| entry_errors(entry, env) }
  end

  def render(entries, env)
    listed = entries.to_set(&:name)
    sections = entries.sort_by(&:name).map { |entry| section(entry, env, listed) }
    [INTRO, *sections].join("\n")
  end

  def unlisted(guides, entries)
    names = entries.map(&:name)
    guides.flat_map do |path, text|
      text.scan(CONSTANT).uniq
          .reject { |constant| names.any? { |name| name == constant || name.start_with?("#{constant}::") } }
          .map { |constant| "#{path} names #{constant}, which public_api.yml doesn't list" }
    end
  end

  private

  def entry_errors(entry, env)
    declaration = lookup(entry.name, env)
    return ["public_api.yml: #{entry.name} is not declared in sig/"] unless declaration
    return [] if entry.method_names.nil?
    unless members?(declaration)
      return ["public_api.yml: #{entry.name} takes no method list: it is not a class, module or interface"]
    end

    missing = entry.method_names - available_methods(declaration, env).map { |member| name_of(member) }
    missing.map { |name| "public_api.yml: #{entry.name} has no public method #{name} in sig/" }
  end

  def lookup(name, env)
    type_name = RBS::TypeName.parse("::#{name}")
    env.class_decls[type_name] || env.interface_decls[type_name] ||
      env.type_alias_decls[type_name] || env.constant_decls[type_name]
  end

  def members?(declaration)
    declaration.is_a?(RBS::Environment::ModuleEntry) || declaration.is_a?(RBS::Environment::ClassEntry) ||
      declaration.is_a?(RBS::Environment::InterfaceEntry)
  end

  def section(entry, env, listed)
    declaration = lookup(entry.name, env)
    out = StringIO.new
    RBS::Writer.new(out: out).write([display(declaration, entry, env, listed)])
    "## `#{entry.name}`\n\n```rbs\n#{out.string}```\n"
  end

  def display(declaration, entry, env, listed)
    name = declaration.name.relative!
    case declaration
    when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
      mixins = public_mixins(declaration, listed)
      members = (mixins + chosen(entry, declaration, env)).map { |member| bare(member) }
      declaration.primary_decl.update(name: name, members: members, annotations: [], location: nil, comment: nil)
    when RBS::Environment::InterfaceEntry
      methods = chosen(entry, declaration, env).map { |member| bare(member) }
      declaration.decl.update(name: name, members: methods, annotations: [], location: nil, comment: nil)
    when RBS::Environment::TypeAliasEntry
      alias_decl = declaration.decl
      RBS::AST::Declarations::TypeAlias.new(
        name: name,
        type_params: alias_decl.type_params,
        type: alias_decl.type,
        annotations: [],
        location: nil,
        comment: nil
      )
    else
      RBS::AST::Declarations::Constant.new(name: name, type: declaration.decl.type, location: nil, comment: nil)
    end
  end

  def chosen(entry, declaration, env)
    return own_methods(declaration) if entry.method_names.nil?

    available_methods(declaration, env)
      .select { |member| entry.method_names.include?(name_of(member)) }
      .uniq { |member| name_of(member) }
  end

  def declarations(declaration)
    declaration.is_a?(RBS::Environment::InterfaceEntry) ? [declaration.decl] : declaration.each_decl.to_a
  end

  def available_methods(declaration, env)
    own_methods(declaration) + included_methods(declaration, env)
  end

  def own_methods(declaration)
    declarations(declaration).flat_map { |decl| public_methods_of(decl.members) }
  end

  def method?(member)
    METHOD.any? { |kind| member.is_a?(kind) } && !forwarding?(member)
  end

  # A `def name: ...` reopening adds no signature of its own.
  def forwarding?(member)
    member.is_a?(RBS::AST::Members::MethodDefinition) && member.overloading? && member.overloads.empty?
  end

  def public_methods_of(members)
    members.reduce([[], :public]) do |(kept, default), member|
      case member
      when RBS::AST::Members::Public then [kept, :public]
      when RBS::AST::Members::Private then [kept, :private]
      else [method?(member) && !private?(member, default) ? [*kept, member] : kept, default]
      end
    end.first
  end

  # A bare `private` or `public` line sets the default for instance members
  # only, as RBS itself reads it.
  def private?(member, default)
    (member.visibility || (member.kind == :instance ? default : :public)) == :private
  end

  def mixins(declaration)
    declarations(declaration).flat_map { |decl| decl.members.grep(MIXIN) }
  end

  def public_mixins(declaration, listed)
    mixins(declaration).select { |mixin| listed.include?(mixin.name.relative!.to_s) }
  end

  def included_methods(declaration, env)
    mixins(declaration).flat_map do |mixin|
      mod = env.class_decls[mixin.name] if mixin.is_a?(RBS::AST::Members::Include)
      next [] unless mod

      substitution = RBS::Substitution.build(mod.type_params.map(&:name), mixin.args)
      (own_methods(mod) + included_methods(mod, env)).map { |member| substitute(member, substitution) }
    end
  end

  def substitute(member, substitution)
    if member.is_a?(RBS::AST::Members::MethodDefinition)
      member.update(overloads: member.overloads.map { |overload| overload.sub(substitution) })
    else
      member.update(type: member.type.sub(substitution))
    end
  end

  def name_of(member)
    name = member.is_a?(RBS::AST::Members::AttrWriter) ? "#{member.name}=" : member.name.to_s
    member.kind == :singleton ? ".#{name}" : name
  end

  # The Writer spaces members by their source lines, which mean nothing once
  # members from different files share a declaration, so locations go too.
  def bare(member)
    if member.is_a?(MIXIN)
      member.class.new(
        name: member.name,
        args: member.args,
        annotations: member.annotations,
        location: nil,
        comment: nil
      )
    else
      member.update(comment: nil, location: nil, visibility: nil)
    end
  end
end
