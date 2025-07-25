# frozen_string_literal: true

RSpec.describe "git base name" do
  it "base_name should strip private repo uris" do
    source = Bundler::Source::Git.new("uri" => "git@github.com:bundler.git")
    expect(source.send(:base_name)).to eq("bundler")
  end

  it "base_name should strip network share paths" do
    source = Bundler::Source::Git.new("uri" => "//MachineName/ShareFolder")
    expect(source.send(:base_name)).to eq("ShareFolder")
  end
end

RSpec.describe "bundle cache with git" do
  it "copies repository to vendor cache and uses it" do
    git = build_git "foo"
    ref = git.ref_for("main", 11)

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    bundle "config set cache_all true"
    bundle :cache
    expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
    expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.git")).not_to exist
    expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.bundlecache")).to be_file

    FileUtils.rm_r lib_path("foo-1.0")
    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "copies repository to vendor cache and uses it even when configured with `path`" do
    git = build_git "foo"
    ref = git.ref_for("main", 11)

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    bundle "config set --local path vendor/bundle"
    bundle "install"
    bundle "config set cache_all true"
    bundle :cache

    expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
    expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.git")).not_to exist

    FileUtils.rm_r lib_path("foo-1.0")
    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "runs twice without exploding" do
    build_git "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    bundle "config set cache_all true"
    bundle :cache
    bundle :cache

    expect(out).to include "Updating files in vendor/cache"
    FileUtils.rm_r lib_path("foo-1.0")
    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "tracks updates" do
    git = build_git "foo"
    old_ref = git.ref_for("main", 11)

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    bundle "config set cache_all true"
    bundle :cache

    update_git "foo" do |s|
      s.write "lib/foo.rb", "puts :CACHE"
    end

    ref = git.ref_for("main", 11)
    expect(ref).not_to eq(old_ref)

    bundle "update", all: true
    bundle :cache

    expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
    expect(bundled_app("vendor/cache/foo-1.0-#{old_ref}")).not_to exist

    FileUtils.rm_r lib_path("foo-1.0")
    run "require 'foo'"
    expect(out).to eq("CACHE")
  end

  it "tracks updates when specifying the gem" do
    git = build_git "foo"
    old_ref = git.ref_for("main", 11)

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    bundle "config set cache_all true"
    bundle :cache

    update_git "foo" do |s|
      s.write "lib/foo.rb", "puts :CACHE"
    end

    ref = git.ref_for("main", 11)
    expect(ref).not_to eq(old_ref)

    bundle "update foo"

    expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
    expect(bundled_app("vendor/cache/foo-1.0-#{old_ref}")).not_to exist

    FileUtils.rm_r lib_path("foo-1.0")
    run "require 'foo'"
    expect(out).to eq("CACHE")
  end

  it "uses the local repository to generate the cache" do
    git = build_git "foo"
    ref = git.ref_for("main", 11)

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-invalid")}', :branch => :main
    G

    bundle %(config set local.foo #{lib_path("foo-1.0")})
    bundle "install"
    bundle "config set cache_all true"
    bundle :cache

    expect(bundled_app("vendor/cache/foo-invalid-#{ref}")).to exist

    # Updating the local still uses the local.
    update_git "foo" do |s|
      s.write "lib/foo.rb", "puts :LOCAL"
    end

    run "require 'foo'"
    expect(out).to eq("LOCAL")
  end

  it "can use gems after copying install folder to a different machine with git not installed" do
    build_git "foo"

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set path vendor/bundle"
    bundle :install

    pristine_system_gems
    with_path_as "" do
      bundle "config set deployment true"
      bundle "install --local"
      expect(the_bundle).to include_gem "foo 1.0"
    end
  end

  it "can install after bundle cache without cloning remote repositories" do
    build_git "foo"

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set cache_all true"
    bundle :cache, "all-platforms" => true

    pristine_system_gems
    bundle "config set frozen true"
    bundle "install --local --verbose"
    expect(out).to_not include("Fetching")
    expect(the_bundle).to include_gem "foo 1.0"
  end

  it "can install after bundle cache without cloning remote repositories even without the original cache" do
    build_git "foo"

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set cache_all true"
    bundle :cache, "all-platforms" => true

    pristine_system_gems
    bundle "config set frozen true"
    bundle "install --local --verbose"
    expect(out).to_not include("Fetching")
    expect(the_bundle).to include_gem "foo 1.0"
  end

  it "can install after bundle cache without cloning remote repositories with only git tracked files" do
    build_git "foo"

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set cache_all true"
    bundle :cache, "all-platforms" => true

    pristine_system_gems
    bundle "config set frozen true"

    # Remove untracked files (including the empty refs dir in the cache)
    Dir.chdir(bundled_app) do
      system(*%W[git init --quiet])
      system(*%W[git add --all])
      system(*%W[git clean -d --force --quiet])
    end

    bundle "install --local --verbose"
    expect(out).to_not include("Fetching")
    expect(the_bundle).to include_gem "foo 1.0"
  end

  it "installs properly a bundler 2.5.17-2.5.23 cache as a bare repository without cloning remote repositories" do
    git = build_git "foo"

    short_ref = git.ref_for("main", 11)
    cache_dir = bundled_app("vendor/cache/foo-1.0-#{short_ref}")

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set global_gem_cache false"
    bundle "config set cache_all true"
    bundle "config path vendor/bundle"
    bundle :install

    # Simulate old cache by copying the real cache folder to vendor/cache
    FileUtils.mkdir_p bundled_app("vendor/cache")
    FileUtils.cp_r "#{Dir.glob(vendored_gems("cache/bundler/git/foo-1.0-*")).first}/.", cache_dir
    FileUtils.rm_r bundled_app("vendor/bundle")

    bundle "install --local --verbose"
    expect(err).to include("Installing from cache in old \"bare repository\" format for compatibility")

    expect(out).to_not include("Fetching")

    # leaves old cache alone
    expect(cache_dir.join("lib/foo.rb")).not_to exist
    expect(cache_dir.join("HEAD")).to exist

    expect(the_bundle).to include_gem "foo 1.0"
  end

  it "migrates a bundler 2.5.17-2.5.23 cache as a bare repository when not running with --local" do
    git = build_git "foo"

    short_ref = git.ref_for("main", 11)
    cache_dir = bundled_app("vendor/cache/foo-1.0-#{short_ref}")

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set global_gem_cache false"
    bundle "config set cache_all true"
    bundle "config path vendor/bundle"
    bundle :install

    # Simulate old cache by copying the real cache folder to vendor/cache
    FileUtils.mkdir_p bundled_app("vendor/cache")
    FileUtils.cp_r "#{Dir.glob(vendored_gems("cache/bundler/git/foo-1.0-*")).first}/.", cache_dir
    FileUtils.rm_r bundled_app("vendor/bundle")

    bundle "install --verbose"
    expect(out).to include("Fetching")

    # migrates old cache alone
    expect(cache_dir.join("lib/foo.rb")).to exist
    expect(cache_dir.join("HEAD")).not_to exist

    expect(the_bundle).to include_gem "foo 1.0"
  end

  it "migrates a bundler 2.5.17-2.5.23 cache as a bare repository when running `bundle cache`, even if gems already installed" do
    git = build_git "foo"

    short_ref = git.ref_for("main", 11)
    cache_dir = bundled_app("vendor/cache/foo-1.0-#{short_ref}")

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set global_gem_cache false"
    bundle "config set cache_all true"
    bundle "config path vendor/bundle"
    bundle :install

    # Simulate old cache by copying the real cache folder to vendor/cache
    FileUtils.mkdir_p bundled_app("vendor/cache")
    FileUtils.cp_r "#{Dir.glob(vendored_gems("cache/bundler/git/foo-1.0-*")).first}/.", cache_dir

    bundle "cache"

    # migrates old cache alone
    expect(cache_dir.join("lib/foo.rb")).to exist
    expect(cache_dir.join("HEAD")).not_to exist

    expect(the_bundle).to include_gem "foo 1.0"
  end

  it "copies repository to vendor cache, including submodules" do
    # CVE-2022-39253: https://lore.kernel.org/lkml/xmqq4jw1uku5.fsf@gitster.g/
    system(*%W[git config --global protocol.file.allow always])

    build_git "submodule", "1.0"

    git = build_git "has_submodule", "1.0" do |s|
      s.add_dependency "submodule"
    end

    git "submodule add #{lib_path("submodule-1.0")} submodule-1.0", lib_path("has_submodule-1.0")
    git "commit -m \"submodulator\"", lib_path("has_submodule-1.0")

    install_gemfile <<-G
      source "https://gem.repo1"
      git "#{lib_path("has_submodule-1.0")}", :submodules => true do
        gem "has_submodule"
      end
    G

    ref = git.ref_for("main", 11)
    bundle "config set cache_all true"
    bundle :cache

    expect(bundled_app("vendor/cache/has_submodule-1.0-#{ref}")).to exist
    expect(bundled_app("vendor/cache/has_submodule-1.0-#{ref}/submodule-1.0")).to exist
    expect(the_bundle).to include_gems "has_submodule 1.0"
  end

  it "caches pre-evaluated gemspecs" do
    git = build_git "foo"

    # Insert a gemspec method that shells out
    spec_lines = lib_path("foo-1.0/foo.gemspec").read.split("\n")
    spec_lines.insert(-2, "s.description = `echo bob`")
    update_git("foo") {|s| s.write "foo.gemspec", spec_lines.join("\n") }

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set cache_all true"
    bundle :cache

    ref = git.ref_for("main", 11)
    gemspec = bundled_app("vendor/cache/foo-1.0-#{ref}/foo.gemspec").read
    expect(gemspec).to_not match("`echo bob`")
  end

  it "can install after bundle cache with git not installed" do
    build_git "foo"

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set cache_all true"
    bundle :cache, "all-platforms" => true, :install => false

    pristine_system_gems
    with_path_as "" do
      bundle "config set deployment true"
      bundle :install, local: true
      expect(the_bundle).to include_gem "foo 1.0"
    end
  end

  it "can install after bundle cache generated with an older Bundler that kept checkouts in the cache" do
    git = build_git("foo")
    locked_revision = git.ref_for("main")
    path_revision = git.ref_for("main", 11)

    git_path = lib_path("foo-1.0")

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{git_path}'
    G
    lockfile <<~L
      GIT
        remote: #{git_path}/
        revision: #{locked_revision}
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    # Simulate an old incorrect situation where vendor/cache would be the install location of git gems
    FileUtils.mkdir_p bundled_app("vendor/cache")
    FileUtils.cp_r git_path, bundled_app("vendor/cache/foo-1.0-#{path_revision}")
    FileUtils.rm_r bundled_app("vendor/cache/foo-1.0-#{path_revision}/.git")

    bundle :install, env: { "BUNDLE_DEPLOYMENT" => "true", "BUNDLE_CACHE_ALL" => "true" }
  end

  it "respects the --no-install flag" do
    git = build_git "foo", &:add_c_extension
    ref = git.ref_for("main", 11)

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set cache_all true"

    # The algorithm for the cache location for a git checkout is
    # in Bundle::Source::Git#cache_path
    cache_path_name = "foo-1.0-#{Digest(:SHA1).hexdigest(lib_path("foo-1.0").to_s)}"

    # Run this test twice. This is because materially different codepaths
    # will get hit the second time around.
    # The first time, Bundler::Sources::Git#install_path is set to the system
    # wide cache directory bundler/gems; the second time, it's set to the
    # vendor/cache directory. We don't want the native extension to appear in
    # either of these places, so run the `bundle cache` command twice.
    2.times do
      bundle :cache, "all-platforms" => true, :install => false

      # it did _NOT_ actually install the gem - neither in $GEM_HOME (bundler 2 mode),
      # nor in .bundle (bundler 4 mode)
      expect(Pathname.new(File.join(default_bundle_path, "gems/foo-1.0-#{ref}"))).to_not exist
      # it _did_ cache the gem in vendor/
      expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
      # it did _NOT_ build the gems extensions in the vendor/ dir
      expect(Dir[bundled_app("vendor/cache/foo-1.0-#{ref}/lib/foo_c*")]).to be_empty
      # it _did_ cache the git checkout
      expect(default_cache_path("git", cache_path_name)).to exist
      # And the checkout is a bare checkout
      expect(default_cache_path("git", cache_path_name, "HEAD")).to exist
    end

    # Subsequently installing the gem should compile it.
    # _currently_, the gem gets compiled in vendor/cache, and vendor/cache is added
    # to the $LOAD_PATH for git extensions, so it all kind of "works". However, in the
    # future we would like to stop adding vendor/cache to the $LOAD_PATH for git extensions
    # and instead treat them identically to normal gems (where the gem install location,
    # not the cache location, is added to $LOAD_PATH).
    # Verify that the compilation worked and the result is in $LOAD_PATH by simply attempting
    # to require it; that should make sure this spec does not break if the load path behaviour
    # is changed.
    bundle :install, local: true
    ruby <<~R, raise_on_error: false
      require 'bundler/setup'
      require 'foo_c'
    R
    expect(last_command).to_not be_failure
  end

  it "doesn't fail when git gem has extensions and an empty cache folder is present before bundle install" do
    build_git "puma" do |s|
      s.add_dependency "rake"
      s.extensions << "Rakefile"
      s.executables = "puma"
      s.write "Rakefile", <<-RUBY
        task :default do
          path = File.expand_path("../lib", __FILE__)
          FileUtils.mkdir_p(path)
          File.open("\#{path}/puma.rb", "w") do |f|
            f.puts "PUMA = 'YES'"
          end
        end
      RUBY
    end

    FileUtils.mkdir_p(bundled_app("vendor/cache"))
    bundle "config set cache_all all"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "puma", :git => "#{lib_path("puma-1.0")}"
    G

    bundle "exec puma"

    expect(out).to eq("YES")
  end
end
