class Cmusfm < Formula
  desc "Last.fm standalone scrobbler for the cmus music player"
  homepage "https://github.com/Arkq/cmusfm"
  url "https://github.com/Arkq/cmusfm/archive/v0.3.3.tar.gz"
  sha256 "9d9fa7df01c3dd7eecd72656e61494acc3b0111c07ddb18be0ad233110833b63"
  head "https://github.com/Arkq/cmusfm.git"

  option "with-debug", "Enable debugging support"

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "pkg-config" => :build
  # depends_on "curl"     # libcurl
  # depends_on "openssl"  # libcrypto, for md5
  depends_on "libnotify" => :optional

  def install
    args = %W[
      --prefix=#{prefix}
      --disable-dependency-tracking
      --disable-silent-rules
    ]
    args << "--enable-debug" if build.with? "debug"
    args << "--enable-libnotify" if build.with? "libnotify"

    system "autoreconf", "--install"
    mkdir "build" do
      system "../configure", *args
      system "make", "install"
    end
  end

  def caveats; <<~EOS
    To grant access to your Last.fm account, run:
      $ cmusfm init

    To configure, edit:
      ~/.config/cmus/cmusfm.conf

    To enable from within cmux, run:
      :set status_display_program=cmusfm
    EOS
  end

  test do
    system "#{bin}/cmusfm"
  end
end
