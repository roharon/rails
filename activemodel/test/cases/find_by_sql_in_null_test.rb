# frozen_string_literal: true
# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  gem "rails", path: "./"
  gem "sqlite3"
end

require "active_record"
require "minitest/autorun"
require "logger"

# This connection will do for database-independent bug reports.
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
    t.string :title
    t.string :description
  end
end

class Post < ActiveRecord::Base
end

class BugTest < Minitest::Test
  def test_find_by_sql_with_not_in_clause
    Post.create!(title: "First Post", description: "description")
    Post.create!(title: "Second Post", description: "description")

    post_ids = []
    posts = Post.find_by_sql(["SELECT * FROM posts WHERE id NOT IN (:post_ids)", post_ids: post_ids])

    posts2 = Post.where.not(id: [])
    p "posts2 => #{posts2.to_sql}"
    assert_equal 2, posts2.count

    assert_equal 2, posts.count
  end
end
