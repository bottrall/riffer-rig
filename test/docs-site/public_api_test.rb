# frozen_string_literal: true

require 'test_helper'
require_relative '../../docs-site/public_api'

describe 'docs-site/public_api.rb' do
  sig = File.expand_path('../fixtures/public_api/sig', __dir__)
  loaded = nil

  define_method(:env) { loaded ||= PublicApi.environment([sig]) }

  define_method(:errors) { |list| PublicApi.errors(PublicApi.entries(list), env) }

  define_method(:document) { |list| PublicApi.render(PublicApi.entries(list), env) }

  define_method(:block) do |name, list = { name => nil }|
    document(list)[/^## `#{Regexp.escape(name)}`\n\n```rbs\n(.*?)```\n/m, 1]
  end

  define_method(:unlisted) { |text, list| PublicApi.unlisted({ 'docs/GUIDE.md' => text }, PublicApi.entries(list)) }

  describe '.entries' do
    it 'takes a bare constant as its whole surface' do
      assert_nil PublicApi.entries('Shop::Order' => nil).first.method_names
    end

    it "keeps a constant's method names" do
      assert_equal %w[place .build], PublicApi.entries('Shop::Order' => %w[place .build]).first.method_names
    end
  end

  describe '.environment' do
    it 'loads the declarations in every directory' do
      assert env.class_decls.key?(RBS::TypeName.parse('::Shop::Order'))
    end
  end

  describe '.errors' do
    it 'reports a constant sig/ does not declare' do
      assert_equal ['public_api.yml: Shop::Basket is not declared in sig/'], errors('Shop::Basket' => nil)
    end

    it 'reports a method list on a constant that has no methods' do
      assert_equal ['public_api.yml: Shop::money takes no method list: it is not a class, module or interface'],
                   errors('Shop::money' => %w[to_s])
    end

    it 'reports a method the constant does not declare' do
      assert_equal ['public_api.yml: Shop::Order has no public method refund in sig/'],
                   errors('Shop::Order' => %w[refund])
    end

    it 'reports a private method' do
      assert_equal ['public_api.yml: Shop::Order has no public method audit in sig/'],
                   errors('Shop::Order' => %w[audit])
    end

    it 'reports a method marked private inline' do
      assert_equal ['public_api.yml: Shop::Order has no public method hidden in sig/'],
                   errors('Shop::Order' => %w[hidden])
    end

    it 'accepts a singleton method declared after a bare private' do
      assert_empty errors('Shop::Order' => %w[.reorder])
    end

    it 'accepts a method declared after a return to public' do
      assert_empty errors('Shop::Order' => %w[cancel])
    end

    it 'tells an instance method from a singleton one' do
      assert_equal ['public_api.yml: Shop::Order has no public method build in sig/'],
                   errors('Shop::Order' => %w[build])
    end

    it 'names a writer with its equals sign' do
      assert_empty errors('Shop::Order' => %w[note=])
    end

    it 'accepts a method from an included module' do
      assert_empty errors('Shop::Order' => %w[label])
    end

    it 'skips an included module sig/ does not declare' do
      assert_equal ['public_api.yml: Shop::Order has no public method between? in sig/'],
                   errors('Shop::Order' => %w[between?])
    end

    it 'does not look in an extended module' do
      assert_equal ['public_api.yml: Shop::Order has no public method .stock in sig/'],
                   errors('Shop::Order' => %w[.stock])
    end

    it 'accepts an interface method' do
      assert_empty errors('Shop::_Payable' => %w[pay])
    end

    it 'accepts a list of declared constants and methods' do
      assert_empty errors('Shop::Order' => %w[place .build total], 'Shop::_Payable' => nil, 'Shop::money' => nil)
    end
  end

  describe '.render' do
    it 'gives the page its title as the first heading' do
      assert_equal 'Public API', document('Shop::Order' => nil)[/^# (.+)$/, 1]
    end

    it 'orders the sections by constant name' do
      headings = document(
        'Shop::Order' => nil,
        'Shop::VERSION' => nil,
        'Shop::Labelled' => nil
      ).scan(/^## `(.+)`$/).flatten

      assert_equal %w[Shop::Labelled Shop::Order Shop::VERSION], headings
    end

    it "renders a bare class's public methods from every file that declares it" do
      expected = <<~RBS
        class Shop::Order
          attr_reader total: Integer

          attr_writer note: String

          def self.build: () -> ::Shop::Order

          def place: () -> void

          def self.reorder: () -> void

          def cancel: () -> void

          def self.restock: () -> void
        end
      RBS

      assert_equal expected, block('Shop::Order')
    end

    it 'shows an included module that is listed' do
      assert_includes block('Shop::Order', 'Shop::Order' => nil, 'Shop::Shared' => nil), 'include ::Shop::Shared'
    end

    it 'renders only the listed methods' do
      expected = <<~RBS
        class Shop::Order
          def self.build: () -> ::Shop::Order

          def place: () -> void
        end
      RBS

      assert_equal expected, block('Shop::Order', 'Shop::Order' => %w[place .build])
    end

    it 'renders a method from an included module with its type arguments' do
      assert_includes block('Shop::Order', 'Shop::Order' => %w[label]), 'def label: () -> String'
    end

    it 'renders an attribute from an included module with its type arguments' do
      assert_includes block('Shop::Order', 'Shop::Order' => %w[code]), 'attr_reader code: String'
    end

    it 'renders an interface under its full name' do
      assert_includes block('Shop::_Payable'), 'interface Shop::_Payable'
    end

    it "resolves a short name in an interface against the interface's namespace" do
      assert_includes block('Shop::_Payable'), 'def pay: (::Shop::money amount) -> void'
    end

    it "renders only an interface's listed methods" do
      refute_includes block('Shop::_Payable', 'Shop::_Payable' => %w[pay]), 'refund'
    end

    it 'renders a type alias' do
      assert_equal "type Shop::money = Integer\n", block('Shop::money')
    end

    it 'renders a constant' do
      assert_equal "Shop::VERSION: String\n", block('Shop::VERSION')
    end
  end

  describe '.unlisted' do
    it 'accepts a listed constant' do
      assert_empty unlisted('Use `Riffer::Rig::Runtime`.', 'Riffer::Rig::Runtime' => nil)
    end

    it 'accepts the namespace of a listed constant' do
      assert_empty unlisted('Call `Riffer::Rig.extension`.', 'Riffer::Rig::Runtime' => nil)
    end

    it 'reports a constant the list leaves out, once' do
      assert_equal ["docs/GUIDE.md names Riffer::Rig::Hosts::_Host, which public_api.yml doesn't list"],
                   unlisted(
                     '`Riffer::Rig::Hosts::_Host` and `Riffer::Rig::Hosts::_Host`',
                     'Riffer::Rig::Runtime' => nil
                   )
    end
  end
end
