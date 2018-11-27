class OpensslAT11 < Formula
  desc "Cryptography and SSL/TLS Toolkit"
  homepage "https://openssl.org/"
  url "https://www.openssl.org/source/openssl-1.1.1a.tar.gz"
  mirror "https://dl.bintray.com/homebrew/mirror/openssl@1.1--1.1.1a.tar.gz"
  mirror "https://www.mirrorservice.org/sites/ftp.openssl.org/source/openssl-1.1.1a.tar.gz"
  sha256 "fc20130f8b7cbd2fb918b2f14e2f429e109c31ddd0fb38fc5d71d9ffed3f9f41"
  version_scheme 1

  keg_only :versioned_formula

  # Only needs 5.10 to run, but needs >5.13.4 to run the testsuite.
  # https://github.com/openssl/openssl/blob/4b16fa791d3ad8/README.PERL
  # The MacOS ML tag is same hack as the way we handle most :python deps.
  depends_on "perl" if MacOS.version <= :mountain_lion

  # SSLv2 died with 1.1.0, so no-ssl2 no longer required.
  # SSLv3 & zlib are off by default with 1.1.0 but this may not
  # be obvious to everyone, so explicitly state it for now to
  # help debug inevitable breakage.
  def configure_args; %W[
    --prefix=#{prefix}
    --openssldir=#{openssldir}
    no-ssl3
    no-ssl3-method
    no-zlib
  ]
  end

  patch :DATA

  def install
    # This could interfere with how we expect OpenSSL to build.
    ENV.delete("OPENSSL_LOCAL_CONFIG_DIR")

    # This ensures where Homebrew's Perl is needed the Cellar path isn't
    # hardcoded into OpenSSL's scripts, causing them to break every Perl update.
    # Whilst our env points to opt_bin, by default OpenSSL resolves the symlink.
    if which("perl") == Formula["perl"].opt_bin/"perl"
      ENV["PERL"] = Formula["perl"].opt_bin/"perl"
    end

    if MacOS.prefer_64_bit?
      arch_args = %w[darwin64-x86_64-cc enable-ec_nistp_64_gcc_128]
    else
      arch_args = %w[darwin-i386-cc]
    end

    ENV.deparallelize
    system "perl", "./Configure", *(configure_args + arch_args)
    system "make"
    system "make", "test"
    system "make", "install", "MANDIR=#{man}", "MANSUFFIX=ssl"
  end

  def openssldir
    etc/"openssl@1.1"
  end

  def post_install
    keychains = %w[
      /System/Library/Keychains/SystemRootCertificates.keychain
    ]

    certs_list = `security find-certificate -a -p #{keychains.join(" ")}`
    certs = certs_list.scan(
      /-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m,
    )

    valid_certs = certs.select do |cert|
      IO.popen("#{bin}/openssl x509 -inform pem -checkend 0 -noout >/dev/null", "w") do |openssl_io|
        openssl_io.write(cert)
        openssl_io.close_write
      end

      $CHILD_STATUS.success?
    end

    openssldir.mkpath
    (openssldir/"cert.pem").atomic_write(valid_certs.join("\n"))
  end

  def caveats; <<~EOS
    A CA file has been bootstrapped using certificates from the system
    keychain. To add additional certificates, place .pem files in
      #{openssldir}/certs

    and run
      #{opt_bin}/c_rehash
  EOS
  end

  test do
    # Make sure the necessary .cnf file exists, otherwise OpenSSL gets moody.
    assert_predicate HOMEBREW_PREFIX/"etc/openssl@1.1/openssl.cnf", :exist?,
            "OpenSSL requires the .cnf file for some functionality"

    # Check OpenSSL itself functions as expected.
    (testpath/"testfile.txt").write("This is a test file")
    expected_checksum = "e2d0fe1585a63ec6009c8016ff8dda8b17719a637405a4e23c0ff81339148249"
    system bin/"openssl", "dgst", "-sha256", "-out", "checksum.txt", "testfile.txt"
    open("checksum.txt") do |f|
      checksum = f.read(100).split("=").last.strip
      assert_equal checksum, expected_checksum
    end
  end
end

__END__
diff --git a/apps/ca.c b/apps/ca.c
index 69207c0662..0b945d7b59 100644
--- a/apps/ca.c
+++ b/apps/ca.c
@@ -1083,6 +1083,20 @@ end_of_options:
                 goto end;
             }
 
+        if (strcmp(startdate, "today") != 0 && !ASN1_UTCTIME_set_string(NULL, startdate)) {
+            BIO_printf(bio_err, "start date is invalid, it should be YYMMDDHHMMSSZ or YYYYMMDDHHMMSSZ\n");
+            goto end;
+        }
+        if (enddate) {
+            crldays = 1;
+            crlhours = 0;
+            crlsec = 0;
+            if (!ASN1_UTCTIME_set_string(NULL, enddate)) {
+                BIO_printf(bio_err, "end date is invalid, it should be YYMMDDHHMMSSZ or YYYYMMDDHHMMSSZ\n");
+                goto end;
+            }
+        }
+
         if (!crldays && !crlhours && !crlsec) {
             if (!NCONF_get_number(conf, section,
                                   ENV_DEFAULT_CRL_DAYS, &crldays))
@@ -1119,6 +1133,11 @@ end_of_options:
 
         ASN1_TIME_free(tmptm);
 
+        if (strcmp(startdate, "today") != 0)
+            ASN1_UTCTIME_set_string(X509_CRL_get_lastUpdate(crl), startdate);
+        if (enddate)
+            ASN1_UTCTIME_set_string(X509_CRL_get_nextUpdate(crl), enddate);
+
         for (i = 0; i < sk_OPENSSL_PSTRING_num(db->db->data); i++) {
             pp = sk_OPENSSL_PSTRING_value(db->db->data, i);
             if (pp[DB_type][0] == DB_TYPE_REV) {
