RubyGems Standalone Installer
=============================

This installer helps you install or update RubyGems, it will fetch the latest
RubyGems tar package, unpack and install it. It does not rely on GNU tar,
however, it does depend on Ruby, with the zlib bindings installed.

Usage:
    ruby -ropen-uri -e "open('http://gist.github.com/{TODO}/raw') { |f| eval(f.read) }"