class Cmusfm < Formula
  desc "Last.fm standalone scrobbler for the cmus music player"
  homepage "https://github.com/Arkq/cmusfm"
  url "https://github.com/Arkq/cmusfm/archive/v0.3.3.tar.gz"
  sha256 "9d9fa7df01c3dd7eecd72656e61494acc3b0111c07ddb18be0ad233110833b63"
  revision 3
  head "https://github.com/Arkq/cmusfm.git"

  option "with-debug", "Enable debugging support"

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "pkg-config" => :build
  # depends_on "curl"     # libcurl
  # depends_on "openssl"  # libcrypto, for md5
  depends_on "libnotify" => :optional

  patch :DATA

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
    libfaketime_c = testpath/"libfaketime.c"
    libfaketime_dylib = testpath/"libfaketime.dylib"
    libfaketime_delta = testpath/".libfaketime.delta.txt"

    libfaketime_c.write <<~EOS
      #define _GNU_SOURCE

      #include <assert.h>
      #include <dlfcn.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>
      #include <time.h>

      typedef time_t (*real_time_t)(time_t *);

      time_t time (time_t *timer) {
        static real_time_t real_time = NULL;
        if (!real_time) {
          assert(real_time = dlsym(RTLD_NEXT, "time"));
        }

        FILE *delta_file = NULL;
        if (!delta_file) {
          char *home_path, *delta_path;
          assert(home_path = getenv("HOME"));
          assert(delta_path = malloc(strlen(home_path) + 24));
          assert(strcpy(delta_path, home_path));
          assert(strcat(delta_path, "/.libfaketime.delta.txt"));
          assert(delta_file = fopen(delta_path, "r"));
        }

        long delta;
        assert(freopen(NULL, "r", delta_file));
        assert(fscanf(delta_file, "%ld", &delta) == 1);

        long fake_time = real_time(NULL) + delta;
        if (timer) *timer = fake_time;
        printf("fake time: %ld\\n", fake_time);
        return fake_time;
      }
    EOS
    system ENV.cc, "-shared", "-fPIC", "-o", libfaketime_dylib, libfaketime_c

    cmus_home = testpath/".config/cmus"
    cmusfm_conf = cmus_home/"cmusfm.conf"
    cmusfm_sock = cmus_home/"cmusfm.socket"
    cmusfm_cache = cmus_home/"cmusfm.cache"

    cmusfm = bin/"cmusfm"
    test_artist = "Test Artist"
    test_title = "Test Title"
    status_args = %W[
      artist #{test_artist}
      title #{test_title}
      duration 260
    ]

    mkpath cmus_home
    touch cmusfm_conf

    begin
      libfaketime_delta.write "0"
      server = fork do
        ENV["DYLD_INSERT_LIBRARIES"] = libfaketime_dylib
        ENV["DYLD_FORCE_FLAT_NAMESPACE"] = "1"
        exec cmusfm, "server"
      end
      loop do
        sleep 0.5
        assert_equal nil, Process.wait(server, Process::WNOHANG)
        break if cmusfm_sock.exist?
      end

      system cmusfm, "status", "playing", *status_args
      sleep 2
      libfaketime_delta.atomic_write "260"
      system cmusfm, "status", "stopped", *status_args
    ensure
      Process.kill :TERM, server
      Process.wait server
    end

    assert_predicate cmusfm_cache, :exist?
    strings = shell_output "strings #{cmusfm_cache}"
    assert_match /^#{test_artist}$/, strings
    assert_match /^#{test_title}$/, strings
  end
end

__END__
diff --git a/src/server.c b/src/server.c
index 80f5e5d..5c180cb 100644
--- a/src/server.c
+++ b/src/server.c
@@ -147,19 +147,16 @@ static void cmusfm_server_process_data(scrobbler_session_t *sbs,
 action_submit:
 		playtime += time(NULL) - unpaused;
 
-		/* Track should be submitted if it is longer than 30 seconds and it has
-		 * been played for at least half its duration (play time is greater than
-		 * 15 seconds or 50% of the track duration respectively). Also the track
-		 * should be submitted if the play time is greater than 4 minutes. */
+		/* Track should be submitted if it has been played for at least half its
+		 * duration (play time is greater than 15 seconds or 50% of the track
+		 * duration respectively). Also the track should be submitted if the
+		 * play time is greater than 4 minutes. */
 		if (started != 0 && (playtime > fulltime - playtime || playtime > 240)) {
 
 			/* playing duration is OK so submit track */
 			set_trackinfo(&sb_tinf, saved_record);
 			sb_tinf.timestamp = started;
 
-			if (sb_tinf.duration <= 30)
-				goto action_submit_skip;
-
 			if ((saved_is_radio && !config.submit_shoutcast) ||
 					(!saved_is_radio && !config.submit_localfile)) {
 				/* skip submission if we don't want it */
