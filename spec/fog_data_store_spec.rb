require 'spec_helper'
require 'dragonfly/spec/data_store_examples'
require 'yaml'
require 'dragonfly/fog_data_store'

describe Dragonfly::FogDataStore do

  # To run these tests, put a file ".fog_spec.yml" in the dragonfly root dir, like this:
  # key: XXXXXXXXXX
  # secret: XXXXXXXXXX
  # enabled: true
  if File.exist?(file = File.expand_path('../../.fog_spec.yml', __FILE__))
    config = YAML.load_file(file)
    KEY = config['key']
    SECRET = config['secret']
    enabled = config['enabled']
  else
    enabled = false
  end
  CONTAINER = 'test-container'

  before(:each) do
    Fog.mock!
    @data_store = Dragonfly::FogDataStore.new(
      provider: 'Rackspace',
      username: 'XXXXXXXXX',
      api_key: 'XXXXXXXXX',
      region: 'ord',
      secret: 'super-secret-key-no-one-can-guess',
      container: CONTAINER
    )
  end

  it_should_behave_like 'data_store'

  let (:app) { Dragonfly.app }
  let (:content) { Dragonfly::Content.new(app, "eggheads") }
  let (:new_content) { Dragonfly::Content.new(app) }

  describe "registering with a symbol" do
    it "registers a symbol for configuring" do
      app.configure do
        datastore :fog
      end
      expect(app.datastore).to be_a(Dragonfly::FogDataStore)
    end
  end

  describe "write" do
    it "should use the name from the content if set" do
      content.name = 'doobie.doo'
      uid = @data_store.write(content)
      expect(uid).to match(/doobie\.doo$/)
      new_content.update(*@data_store.read(uid))
      expect(new_content.data).to eq('eggheads')
    end

    it "should work ok with files with funny names" do
      content.name = "A Picture with many spaces in its name (at 20:00 pm).png"
      uid = @data_store.write(content)
      expect(uid).to match(/A_Picture_with_many_spaces_in_its_name_at_20_00_pm_\.png$/)
      new_content.update(*@data_store.read(uid))
      expect(new_content.data).to eq('eggheads')
    end

    it "should allow for setting the path manually" do
      uid = @data_store.write(content, path: 'hello/there')
      expect(uid).to eq('hello/there')
      new_content.update(*@data_store.read(uid))
      expect(new_content.data).to eq('eggheads')
    end

  end

  describe "not configuring stuff properly" do
    it "should require a container name on write" do
      @data_store.container = nil
      expect{ @data_store.write(content) }.to raise_error(Dragonfly::FogDataStore::NotConfigured)
    end

    it "should require an username on write" do
      @data_store.username = nil
      expect{ @data_store.write(content) }.to raise_error(Dragonfly::FogDataStore::NotConfigured)
    end

    it "should require a secret access key on write" do
      @data_store.api_key = nil
      expect{ @data_store.write(content) }.to raise_error(Dragonfly::FogDataStore::NotConfigured)
    end

    it "should require a container name on read" do
      @data_store.container = nil
      expect{ @data_store.read('asdf') }.to raise_error(Dragonfly::FogDataStore::NotConfigured)
    end

    it "should require an username on read" do
      @data_store.username = nil
      expect{ @data_store.read('asdf') }.to raise_error(Dragonfly::FogDataStore::NotConfigured)
    end

    it "should require a secret access key on read" do
      @data_store.api_key = nil
      expect{ @data_store.read('asdf') }.to raise_error(Dragonfly::FogDataStore::NotConfigured)
    end
  end

  describe "autocreating the container" do
    it "should create the container on write if it doesn't exist" do
      @data_store.container = "dragonfly-test-blah-blah-#{rand(100000000)}"
      @data_store.write(content)
    end

    it "should not try to create the container on read if it doesn't exist" do
      @data_store.container = "dragonfly-test-blah-blah-#{rand(100000000)}"
      expect(@data_store.send(:storage)).to_not receive(:put_container)
      expect(@data_store.read("gungle")).to be_nil
    end
  end

  describe "headers" do
    before(:each) do
      @data_store.storage_headers = {'x-fog-foo' => 'biscuithead'}
    end

    it "should allow configuring globally" do
      expect(@data_store.storage).to receive(:put_object).with(CONTAINER, anything, anything,
                                                           hash_including('x-fog-foo' => 'biscuithead')
                                                          )
      @data_store.write(content)
    end

    it "should allow adding per-store" do
      expect(@data_store.storage).to receive(:put_object).with(CONTAINER, anything, anything,
                                                           hash_including('x-fog-foo' => 'biscuithead', 'hello' => 'there')
                                                          )
      @data_store.write(content, headers: {'hello' => 'there'})
    end

    it "should let the per-store one take precedence" do
      expect(@data_store.storage).to receive(:put_object).with(CONTAINER, anything, anything,
                                                           hash_including('x-fog-foo' => 'override!')
                                                          )
      @data_store.write(content, headers: {'x-fog-foo' => 'override!'})
    end

    it "should write setting the content type" do
      expect(@data_store.storage).to receive(:put_object) do |_, __, ___, headers|
        expect(headers['Content-Type']).to eq('image/png')
      end
      content.name = 'egg.png'
      @data_store.write(content)
    end

    it "allow overriding the content type" do
      expect(@data_store.storage).to receive(:put_object) do |_, __, ___, headers|
        expect(headers['Content-Type']).to eq('text/plain')
      end
      content.name = 'egg.png'
      @data_store.write(content, headers: {'Content-Type' => 'text/plain'})
    end
  end

  describe "meta" do
    it "uses the X-Object-Meta header for meta" do
      uid = @data_store.write(content, headers: {'X-Object-Meta' => Dragonfly::Serializer.json_encode({potato: 44})})
      c, meta = @data_store.read(uid)
      expect(meta['potato']).to eq(44)
    end
  end

end
