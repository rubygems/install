##
#
#   RubyGems Standalone Installer
#   =============================
#
#   This installer helps you install or update RubyGems, it will fetch the
#   latest RubyGems tar package, unpack and install it. It does not rely on
#   GNU tar, however, it does depend on Ruby, with the zlib bindings
#   installed.
#
#   Usage:
#     ruby -ropen-uri -e "open('http://gist.github.com/{TODO}/raw') { |f| eval(f.read) }"
#

#++
# Copyright (C) 2010 James Tucker, RubyGems Team
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt from the RubyGems package for additional licensing
# information.
#--

require 'open-uri'
require 'zlib'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'

module Gem; end

module Gem::Package
  class Error < StandardError; end
  class NonSeekableIO < Error; end
  class ClosedIO < Error; end
  class BadCheckSum < Error; end
  class TooLongFileName < Error; end
  class FormatError < Error; end
end

class Gem::Package::TarReader
  include Gem::Package
  class UnexpectedEOF < StandardError; end

  def self.new(io)
    reader = super
    return reader unless block_given?
    begin
      yield reader
    ensure
      reader.close
    end
    nil
  end

  def initialize(io)
    @io = io
    @init_pos = io.pos
  end

  def close
  end

  def each
    loop do
      return if @io.eof?

      header = Gem::Package::TarHeader.from @io
      return if header.empty?

      entry = Gem::Package::TarReader::Entry.new header, @io
      size = entry.header.size

      yield entry

      skip = (512 - (size % 512)) % 512
      pending = size - entry.bytes_read

      begin

        @io.seek pending, IO::SEEK_CUR
        pending = 0
      rescue Errno::EINVAL, NameError
        while pending > 0 do
          bytes_read = @io.read([pending, 4096].min).size
          raise UnexpectedEOF if @io.eof?
          pending -= bytes_read
        end
      end

      @io.read skip # discard trailing zeros

      entry.close
    end
  end

  alias each_entry each

  def rewind
    if @init_pos == 0 then
      raise Gem::Package::NonSeekableIO unless @io.respond_to? :rewind
      @io.rewind
    else
      raise Gem::Package::NonSeekableIO unless @io.respond_to? :pos=
      @io.pos = @init_pos
    end
  end

end

class Gem::Package::TarReader::Entry

  attr_reader :header

  def initialize(header, io)
    @closed = false
    @header = header
    @io = io
    @orig_pos = @io.pos
    @read = 0
  end

  def check_closed # :nodoc:
    raise IOError, "closed #{self.class}" if closed?
  end

  def bytes_read
    @read
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end

  def eof?
    check_closed

    @read >= @header.size
  end

  def full_name
    if @header.prefix != "" then
      File.join @header.prefix, @header.name
    else
      @header.name
    end
  end

  def getc
    check_closed

    return nil if @read >= @header.size

    ret = @io.getc
    @read += 1 if ret

    ret
  end

  def directory?
    @header.typeflag == "5"
  end

  def file?
    @header.typeflag == "0"
  end

  def pos
    check_closed

    bytes_read
  end

  def read(len = nil)
    check_closed

    return nil if @read >= @header.size

    len ||= @header.size - @read
    max_read = [len, @header.size - @read].min

    ret = @io.read max_read
    @read += ret.size

    ret
  end

  def rewind
    check_closed

    raise Gem::Package::NonSeekableIO unless @io.respond_to? :pos=

    @io.pos = @orig_pos
    @read = 0
  end

end

class Gem::Package::TarHeader

  FIELDS = [
    :checksum,
    :devmajor,
    :devminor,
    :gid,
    :gname,
    :linkname,
    :magic,
    :mode,
    :mtime,
    :name,
    :prefix,
    :size,
    :typeflag,
    :uid,
    :uname,
    :version,
  ]

  PACK_FORMAT = 'a100' + # name
  'a8'   + # mode
  'a8'   + # uid
  'a8'   + # gid
  'a12'  + # size
  'a12'  + # mtime
  'a7a'  + # chksum
  'a'    + # typeflag
  'a100' + # linkname
  'a6'   + # magic
  'a2'   + # version
  'a32'  + # uname
  'a32'  + # gname
  'a8'   + # devmajor
  'a8'   + # devminor
  'a155'   # prefix

  UNPACK_FORMAT = 'A100' + # name
  'A8'   + # mode
  'A8'   + # uid
  'A8'   + # gid
  'A12'  + # size
  'A12'  + # mtime
  'A8'   + # checksum
  'A'    + # typeflag
  'A100' + # linkname
  'A6'   + # magic
  'A2'   + # version
  'A32'  + # uname
  'A32'  + # gname
  'A8'   + # devmajor
  'A8'   + # devminor
  'A155'   # prefix

  attr_reader(*FIELDS)

  def self.from(stream)
    header = stream.read 512
    empty = (header == "\0" * 512)

    fields = header.unpack UNPACK_FORMAT

    name     = fields.shift
    mode     = fields.shift.oct
    uid      = fields.shift.oct
    gid      = fields.shift.oct
    size     = fields.shift.oct
    mtime    = fields.shift.oct
    checksum = fields.shift.oct
    typeflag = fields.shift
    linkname = fields.shift
    magic    = fields.shift
    version  = fields.shift.oct
    uname    = fields.shift
    gname    = fields.shift
    devmajor = fields.shift.oct
    devminor = fields.shift.oct
    prefix   = fields.shift

    new :name     => name,
    :mode     => mode,
    :uid      => uid,
    :gid      => gid,
    :size     => size,
    :mtime    => mtime,
    :checksum => checksum,
    :typeflag => typeflag,
    :linkname => linkname,
    :magic    => magic,
    :version  => version,
    :uname    => uname,
    :gname    => gname,
    :devmajor => devmajor,
    :devminor => devminor,
    :prefix   => prefix,

    :empty    => empty

  end

  def initialize(vals)
    unless vals[:name] && vals[:size] && vals[:prefix] && vals[:mode] then
      raise ArgumentError, ":name, :size, :prefix and :mode required"
    end

    vals[:uid] ||= 0
    vals[:gid] ||= 0
    vals[:mtime] ||= 0
    vals[:checksum] ||= ""
    vals[:typeflag] ||= "0"
    vals[:magic] ||= "ustar"
    vals[:version] ||= "00"
    vals[:uname] ||= "wheel"
    vals[:gname] ||= "wheel"
    vals[:devmajor] ||= 0
    vals[:devminor] ||= 0

    FIELDS.each do |name|
      instance_variable_set "@#{name}", vals[name]
    end

    @empty = vals[:empty]
  end

  def empty?
    @empty
  end

  def ==(other) # :nodoc:
    self.class === other and
    @checksum == other.checksum and
    @devmajor == other.devmajor and
    @devminor == other.devminor and
    @gid      == other.gid      and
    @gname    == other.gname    and
    @linkname == other.linkname and
    @magic    == other.magic    and
    @mode     == other.mode     and
    @mtime    == other.mtime    and
    @name     == other.name     and
    @prefix   == other.prefix   and
    @size     == other.size     and
    @typeflag == other.typeflag and
    @uid      == other.uid      and
    @uname    == other.uname    and
    @version  == other.version
  end

  def to_s # :nodoc:
    update_checksum
    header
  end

  def update_checksum
    header = header " " * 8
    @checksum = oct calculate_checksum(header), 6
  end

  private

  def calculate_checksum(header)
    header.unpack("C*").inject { |a, b| a + b }
  end

  def header(checksum = @checksum)
    header = [
      name,
      oct(mode, 7),
      oct(uid, 7),
      oct(gid, 7),
      oct(size, 11),
      oct(mtime, 11),
      checksum,
      " ",
      typeflag,
      linkname,
      magic,
      oct(version, 2),
      uname,
      gname,
      oct(devmajor, 7),
      oct(devminor, 7),
      prefix
    ]

    header = header.pack PACK_FORMAT

    header << ("\0" * ((512 - header.size) % 512))
  end

  def oct(num, len)
    "%0#{len}o" % num
  end

end

module TgzUnpacker
  def self.unpack(zipfile)
    Zlib::GzipReader.open(zipfile) do |gz|
      tar = Gem::Package::TarReader.new(gz)
      tar.each do |entry|
        puts entry.full_name
        case
        when entry.directory?
          Dir.mkdir entry.full_name
        when entry.file?
          open(entry.full_name, 'w') { |f| f.write entry.read }
        end
      end
    end
  end
end

begin
  latest_uri = "http://github.com/rubygems/rubygems/tarball/master"
  latest_tgz_file = 'rubygems-master.tgz'

  working_dir = Dir.tmpdir
  dir = nil

  puts "Working in: #{working_dir}"

  Dir.chdir working_dir do
    print "Fetching rubygems: #{latest_uri}..."; $stdout.flush
    open(latest_uri) {|r| open(latest_tgz_file, 'wb') {|l| l.write r.read } }
    puts "done."

    print "Unpacking #{latest_tgz_file}..."; $stdout.flush
    TgzUnpacker.unpack(latest_tgz_file)
    puts "done."

    rb = File.join(Config::CONFIG.values_at *%w[bindir ruby_install_name])

    dir = Dir['./rubygems-rubygems-*'].sort_by { |d| File.mtime(d) }.last
    cmd = [rb, 'setup.rb', 'install']

    unless RUBY_PLATFORM =~ /mswin|mingw|cygwin/ ||
      Process.euid == 0 || ENV['GEM_HOME']
      puts "About to sudo in order to install to system path..."
      cmd.unshift 'sudo'
    end

    Dir.chdir(dir) { system *cmd }
  end

ensure
  return if $DEBUG
  File.delete(File.join(working_dir, latest_tgz_file))
  FileUtils.rm_rf(File.join(working_dir, dir)) if dir
end