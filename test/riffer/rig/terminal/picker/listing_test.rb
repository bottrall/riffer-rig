# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Picker::Listing do
  def session(title)
    Riffer::Rig::Terminal::Session.new(id: "id-#{title}", title: title, updated: nil, cwd: '/work/proj')
  end

  def listing(*titles, filter: '')
    Riffer::Rig::Terminal::Picker::Listing.new(rows: titles.map { |title| session(title) }, filter: filter)
  end

  def titles(sessions) = sessions.map(&:title)

  it 'is frozen' do
    assert_predicate listing('alpha'), :frozen?
  end

  it 'starts unfiltered' do
    assert_equal '', Riffer::Rig::Terminal::Picker::Listing.new(rows: []).filter
  end

  describe '#shown' do
    it 'shows every row without a filter' do
      assert_equal %w[alpha beta], titles(listing('alpha', 'beta').shown)
    end

    it 'shows the rows whose titles contain the filter, ignoring case' do
      assert_equal %w[Beta], titles(listing('alpha', 'Beta', filter: 'bET').shown)
    end
  end

  describe '#any_match?' do
    it 'matches a filter some title contains' do
      assert listing('alpha', 'beta').any_match?('BET')
    end

    it 'does not match a filter no title contains' do
      refute listing('alpha', 'beta').any_match?('zzz')
    end
  end

  describe '#narrow' do
    it 'takes the new filter' do
      assert_equal 'bet', listing('alpha', 'beta').narrow('bet').filter
    end
  end

  describe '#relist' do
    it 'takes the new rows' do
      assert_equal %w[gamma], titles(listing('alpha').relist([session('gamma')]).rows)
    end

    it 'keeps the filter when a new row matches it' do
      assert_equal 'al', listing('alpha', 'beta', filter: 'al').relist([session('alfa')]).filter
    end

    it 'clears the filter when no new row matches it' do
      assert_equal '', listing('alpha', 'beta', filter: 'bet').relist([session('alpha')]).filter
    end
  end
end
