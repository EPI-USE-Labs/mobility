require "spec_helper"

describe Mobility::Backend::Cache do
  let(:backend_class) do
    Class.new(Mobility::Backend::Null) do
      def read(*args)
        backend_double.read(*args)
      end

      def write(*args)
        backend_double.write(*args)
      end

      def backend_double
        @backend_double ||= RSpec::Mocks::Double.new("backend")
      end
    end
  end
  let(:cached_backend_class) { Class.new(backend_class).include(described_class) }
  let(:options) { { these: "options" } }

  describe "#read" do
    it "caches reads" do
      backend = cached_backend_class.new("model", "attribute")
      expect(backend.backend_double).to receive(:read).once.with(:fr, options).and_return("foo")
      2.times { expect(backend.read(:fr, options)).to eq("foo") }
    end

    it "always returns from cache if backend defines write_to_cache? to return true" do
      cache = double("cache")
      backend_class.class_eval do
        def write_to_cache?
          true
        end

        define_method :new_cache do
          cache
        end
      end
      backend = cached_backend_class.new("model", "attribute")
      expect(backend.backend_double).not_to receive(:read)
      expect(cache).to receive(:[]).twice.with(:fr).and_return("foo")
      2.times { expect(backend.read(:fr, options)).to eq("foo") }
    end
  end

  describe "#write" do
    it "returns value fetched from backend" do
      backend = cached_backend_class.new("model", "attribute")
      expect(backend.backend_double).to receive(:write).twice.with(:fr, "foo", options).and_return("bar")
      2.times { expect(backend.write(:fr, "foo", options)).to eq("bar") }
    end

    it "stores value fetched from backend in cache" do
      cache = double("cache")
      backend_class.class_eval do
        def write_to_cache?
          true
        end

        define_method :new_cache do
          cache
        end
      end
      backend = cached_backend_class.new("model", "attribute")
      expect(backend.backend_double).not_to receive(:write)
      expect(cache).to receive(:[]=).twice.with(:fr, "foo")
      2.times { expect(backend.write(:fr, "foo", options)).to eq("foo") }
    end
  end

  describe "#clear_cache" do
    it "reads from backend after cache cleared" do
      backend = cached_backend_class.new("model", "attribute")
      expect(backend.backend_double).to receive(:read).twice.with(:fr, options).and_return("foo")
      2.times { expect(backend.read(:fr, options)).to eq("foo") }
      backend.clear_cache
      expect(backend.read(:fr, options)).to eq("foo")
    end
  end

  context "ActiveRecord model", orm: :active_record do
    before do
      stub_const 'Article', Class.new(ActiveRecord::Base)
      Article.include Mobility
    end

    context "with one backend" do
      before do
        Article.translates :title, backend: backend_class, cache: true
        @article = Article.create
      end

      shared_examples_for "cache that resets on model action" do |action, options = nil|
        it "updates backend cache on #{action}" do
          backend = @article.mobility_backend_for("title")

          aggregate_failures "reading and writing" do
            expect(backend.backend_double).to receive(:write).with(:en, "foo", {}).and_return("foo set")
            backend.write(:en, "foo")
            expect(backend.read(:en)).to eq("foo set")
          end

          aggregate_failures "resetting model" do
            options ? @article.send(action, options) : @article.send(action)
            expect(backend.backend_double).to receive(:read).with(:en, {}).and_return("from backend")
            expect(backend.read(:en)).to eq("from backend")
          end
        end
      end

      it_behaves_like "cache that resets on model action", :reload
      it_behaves_like "cache that resets on model action", :reload, { readonly: true, lock: true }
      it_behaves_like "cache that resets on model action", :save
    end

    context "with multiple backends" do
      before do
        other_backend = Class.new(backend_class)
        Article.translates :title,   backend: backend_class, cache: true
        Article.translates :content, backend: other_backend, cache: true
        @article = Article.create
      end

      shared_examples_for "cache that resets on model action" do |action, options = nil|
        it "updates cache on both backends on #{action}" do
          title_backend = @article.mobility_backend_for("title")
          content_backend = @article.mobility_backend_for("content")

          aggregate_failures "reading and writing" do
            expect(title_backend.backend_double).to receive(:write).with(:en, "foo", {}).and_return("foo set")
            expect(content_backend.backend_double).to receive(:write).with(:en, "bar", {}).and_return("bar set")
            title_backend.write(:en, "foo")
            content_backend.write(:en, "bar")
            expect(title_backend.read(:en)).to eq("foo set")
            expect(content_backend.read(:en)).to eq("bar set")
          end

          aggregate_failures "resetting model" do
            options ? @article.send(action, options) : @article.send(action)
            expect(title_backend.backend_double).to receive(:read).with(:en, {}).and_return("from title backend")
            expect(title_backend.read(:en)).to eq("from title backend")
            expect(content_backend.backend_double).to receive(:read).with(:en, {}).and_return("from content backend")
            expect(content_backend.read(:en)).to eq("from content backend")
          end
        end
      end

      it_behaves_like "cache that resets on model action", :reload
      it_behaves_like "cache that resets on model action", :reload, { readonly: true, lock: true }
      it_behaves_like "cache that resets on model action", :save
    end
  end
end
