#!/usr/bin/env python3
"""
Install Alpine Linux into the appliance VM, unattended.

    ./scripts/host/install-alpine.py

The VM must already exist and be booted from the Alpine ISO; that is what
scripts/host/create-vm.sh does. This script drives the serial console exactly
the way a person would, and echoes everything it sees, so you can watch it.

What it does, in order:
  1. logs into the live system
  2. brings the uplink up and CHECKS that the package mirror is reachable
     (this is where a wrong address or bridge shows up, not 5 minutes later)
  3. runs setup-alpine from a generated answer file
  4. writes the final network config and your SSH keys onto the new disk
  5. powers off, ejects the ISO and boots from disk

Requires: python3-pexpect   (Debian/Ubuntu: sudo apt install python3-pexpect)
"""
import os
import subprocess
import sys
import time

try:
    import pexpect
except ImportError:
    sys.exit("error: python3-pexpect is not installed.\n"
             "       Debian/Ubuntu: sudo apt install python3-pexpect\n"
             "       Fedora:        sudo dnf install python3-pexpect\n"
             "       Arch:          sudo pacman -S python-pexpect")

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# A prompt of our own. setup-alpine changes the hostname halfway through, which
# changes the shell prompt from "localhost:~#" to "<hostname>:~#" - matching on
# the default prompt makes the installer hang right after a successful install.
PROMPT = "VDEINSTALL# "
ENV = dict(os.environ, LC_ALL="C", LANG="C")


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, env=ENV)


def cfg(*names):
    """Read variables out of config.sh instead of reimplementing shell syntax."""
    script = ". ./config.sh; " + "; ".join('printf "%%s\\n" "${%s-}"' % n for n in names)
    r = subprocess.run(["sh", "-c", script], cwd=REPO, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("error: could not read config.sh\n" + r.stderr)
    return r.stdout.split("\n")[:len(names)]


(VM_NAME, HOSTNAME, WAN_IF, WAN_MODE, WAN_ADDR, WAN_NETMASK, WAN_GATEWAY,
 UPSTREAM_DNS, ROOT_PASSWORD, TIMEZONE, KEYMAP, ALPINE_BRANCH, APK_MIRROR,
 SSH_PUBKEYS, LAN_DOMAIN) = cfg(
    "VM_NAME", "HOSTNAME", "WAN_IF", "WAN_MODE", "WAN_ADDR", "WAN_NETMASK",
    "WAN_GATEWAY", "UPSTREAM_DNS", "ROOT_PASSWORD", "TIMEZONE", "KEYMAP",
    "ALPINE_BRANCH", "APK_MIRROR", "SSH_PUBKEYS", "LAN_DOMAIN")

keys = []
for path in SSH_PUBKEYS.split():
    path = os.path.expanduser(path)
    if os.path.exists(path):
        keys.append(open(path).read().strip())
    else:
        print("note: no such public key, skipping: %s" % path)
if not keys:
    sys.exit("error: none of the files in SSH_PUBKEYS exist.\n"
             "       Make a key first:  ssh-keygen -t ed25519\n"
             "       then point SSH_PUBKEYS in config.sh at the .pub file.")

# Only the uplink is configured here. The isolated interface is set up later by
# scripts/guest/10-router.sh, once the machine can be reached over SSH.
#
# Note the real newlines. Answer files are sourced by the shell, so a quoted
# multi-line value is fine, and it avoids depending on how a given Alpine
# release expands "\n" escapes - get that wrong and the installed machine comes
# up with no address at all.
if WAN_MODE == "dhcp":
    INTERFACES = ("auto lo\niface lo inet loopback\n\n"
                  "auto {0}\niface {0} inet dhcp\n").format(WAN_IF)
else:
    INTERFACES = ("auto lo\niface lo inet loopback\n\n"
                  "auto {0}\niface {0} inet static\n"
                  "    address {1}\n    netmask {2}\n    gateway {3}\n"
                  ).format(WAN_IF, WAN_ADDR, WAN_NETMASK, WAN_GATEWAY)

ANSWERS = """KEYMAPOPTS="{keymap}"
HOSTNAMEOPTS="-n {hostname}"
INTERFACESOPTS="{ifopts}"
DNSOPTS="-d {domain} {dns}"
TIMEZONEOPTS="-z {tz}"
PROXYOPTS="none"
APKREPOSOPTS="{mirror}/{branch}/main {mirror}/{branch}/community"
USEROPTS="none"
SSHDOPTS="-c openssh"
NTPOPTS="chrony"
DISKOPTS="-m sys /dev/vda"
""".format(keymap=KEYMAP, hostname=HOSTNAME, ifopts=INTERFACES,
           domain=LAN_DOMAIN, dns=UPSTREAM_DNS, tz=TIMEZONE,
           mirror=APK_MIRROR, branch=ALPINE_BRANCH)


class Console:
    """Thin wrapper so every step reads the same and errors are legible."""

    def __init__(self, vm):
        self.c = pexpect.spawn("virsh console %s --force" % vm,
                               encoding="utf-8", codec_errors="replace",
                               dimensions=(24, 140), timeout=120, env=ENV)
        self.c.logfile_read = sys.stdout

    def wait(self, pattern, timeout=120, what=""):
        try:
            return self.c.expect(pattern, timeout=timeout)
        except (pexpect.TIMEOUT, pexpect.EOF):
            sys.exit("\n\nerror: timed out waiting for %s\n"
                     "       Attach to the machine and see what it is doing:\n"
                     "           virsh console %s\n"
                     % (what or repr(pattern), VM_NAME))

    def run(self, cmd, timeout=120, what=""):
        self.c.sendline(cmd)
        self.wait(PROMPT, timeout, what or ("command: " + cmd[:60]))

    def heredoc(self, path, text, timeout=60):
        self.c.sendline("cat > %s <<'VDE_EOF'\n%sVDE_EOF" % (path, text))
        self.wait(PROMPT, timeout, "the shell to accept " + path)

    def probe(self, cmd, timeout=90, fail_msg=""):
        """Run cmd; it must print OK. Anything else aborts with fail_msg."""
        self.c.sendline("{ %s ; } && echo VDE_OK || echo VDE_FAIL" % cmd)
        i = self.wait(["VDE_OK", "VDE_FAIL"], timeout, "the result of: " + cmd[:60])
        self.wait(PROMPT, 60)
        if i == 1:
            sys.exit("\n\nerror: " + fail_msg)


def main():
    if sh(["virsh", "domstate", VM_NAME]).returncode != 0:
        sys.exit("error: domain '%s' does not exist.\n"
                 "       Run ./scripts/host/create-vm.sh first." % VM_NAME)
    if "running" not in sh(["virsh", "domstate", VM_NAME]).stdout:
        print("==> starting %s" % VM_NAME)
        sh(["virsh", "start", VM_NAME])

    con = Console(VM_NAME)

    print("\n==> waiting for the live system (this takes about a minute)")
    con.c.sendline("")
    con.wait(r"localhost login:", 420, "the Alpine live system to boot")
    con.c.sendline("root")
    con.wait(r"localhost:~#", 60, "a root shell")
    con.c.sendline("export PS1='%s'" % PROMPT)
    con.wait(PROMPT, 30)
    con.wait(PROMPT, 30)

    print("\n==> bringing up the uplink")
    con.heredoc("/etc/network/interfaces", INTERFACES)
    con.run("printf 'nameserver %s\\n' > /etc/resolv.conf" % UPSTREAM_DNS)
    con.run("rc-service networking restart >/dev/null 2>&1; ip -o -4 addr show %s" % WAN_IF,
            timeout=120)

    target = WAN_GATEWAY if WAN_MODE != "dhcp" else UPSTREAM_DNS
    mirror_host = APK_MIRROR.split("//", 1)[-1].split("/", 1)[0]

    print("\n==> checking connectivity before we commit to an install")
    con.probe("ip -o -4 addr show %s | grep -q inet" % WAN_IF, 60,
              "interface '%s' has no IPv4 address.\n"
              "       On a VM: is HOST_BRIDGE=%s really a bridge on your LAN?\n"
              "       Run 'ip -br addr' on the host to check.\n"
              % (WAN_IF, "(see config.sh)"))
    con.probe("ping -c2 -W3 %s >/dev/null 2>&1" % target, 60,
              "cannot reach %s.\n"
              "       Check WAN_ADDR / WAN_NETMASK / WAN_GATEWAY in config.sh.\n"
              "       Also make sure no other machine already uses %s.\n"
              % (target, WAN_ADDR))
    con.probe("nslookup %s >/dev/null 2>&1" % mirror_host, 60,
              "%s cannot resolve %s.\n"
              "       Set UPSTREAM_DNS in config.sh to a resolver this machine\n"
              "       can actually use - usually your router's address.\n"
              % (UPSTREAM_DNS, mirror_host))
    print("\n    network is up and the mirror resolves. Good.")

    print("\n==> installing Alpine (pulls ~150 MB, give it a few minutes)")
    con.heredoc("/tmp/answers", ANSWERS)
    con.c.sendline("setup-alpine -e -f /tmp/answers")
    while True:
        i = con.wait([r"New password:", r"Retype password:",
                      r"WARNING: Erase the above disk.*",
                      r"Installation is complete",
                      r"ERROR: unable to select packages"],
                     900, "setup-alpine to finish")
        if i in (0, 1):
            con.c.sendline(ROOT_PASSWORD)
        elif i == 2:
            con.c.sendline("y")
        elif i == 3:
            break
        else:
            sys.exit("\n\nerror: apk could not download packages.\n"
                     "       The mirror was reachable a moment ago, so this is\n"
                     "       usually a wrong ALPINE_BRANCH in config.sh.\n"
                     "       It must match the ISO you booted, e.g. v3.24.\n")
    con.wait(PROMPT, 120, "a shell prompt after the install")

    print("\n==> writing the network config and your SSH keys onto the new disk")
    con.probe("mount /dev/vda3 /mnt", 60,
              "could not mount the new root filesystem (/dev/vda3).\n"
              "       Attach with 'virsh console %s', run 'lsblk', and mount the\n"
              "       root partition on /mnt by hand.\n" % VM_NAME)
    con.run("mkdir -p /mnt/root/.ssh")
    con.heredoc("/mnt/etc/network/interfaces", INTERFACES)
    con.run("printf 'search %s\\nnameserver %s\\n' > /mnt/etc/resolv.conf"
            % (LAN_DOMAIN, UPSTREAM_DNS))
    con.heredoc("/mnt/root/.ssh/authorized_keys", "\n".join(keys) + "\n")
    con.run("chmod 700 /mnt/root/.ssh && chmod 600 /mnt/root/.ssh/authorized_keys")

    print("\n==> keeping the serial console enabled on the installed system")
    con.run("grep -q ttyS0 /mnt/etc/update-extlinux.conf || "
            "sed -i 's|^default_kernel_opts=\"|default_kernel_opts=\"console=ttyS0,115200 |' "
            "/mnt/etc/update-extlinux.conf")
    con.run("chroot /mnt extlinux --update /boot", timeout=180)
    con.run("sync; umount /mnt", timeout=120)

    print("\n==> powering off")
    con.c.sendline("poweroff")
    try:
        con.c.expect(pexpect.EOF, timeout=180)
    except pexpect.TIMEOUT:
        pass
    for _ in range(90):
        if "shut off" in sh(["virsh", "domstate", VM_NAME]).stdout:
            break
        time.sleep(2)

    # A fresh install means a fresh host key. Without this, the very next
    # thing the user does - ssh to the machine - fails with a scary
    # "REMOTE HOST IDENTIFICATION HAS CHANGED" warning.
    known = os.path.expanduser("~/.ssh/known_hosts")
    if os.path.exists(known):
        for name in {WAN_ADDR, HOSTNAME, "%s.%s" % (HOSTNAME, LAN_DOMAIN)}:
            if name:
                sh(["ssh-keygen", "-q", "-f", known, "-R", name])
        print("\n==> forgot the old SSH host key for this machine")

    print("\n==> ejecting the ISO and booting from disk")
    for dev in ("sda", "sdb", "hda"):
        if sh(["virsh", "change-media", VM_NAME, dev, "--eject", "--config"]).returncode == 0:
            print("    ejected %s" % dev)
            break
    sh(["virsh", "start", VM_NAME])

    where = WAN_ADDR if WAN_MODE != "dhcp" else HOSTNAME

    # Wait for sshd, then record the new host key so the user's first
    # connection does not stop on "are you sure you want to continue".
    if WAN_MODE != "dhcp":
        print("\n==> waiting for SSH on %s" % where)
        import socket
        for _ in range(60):
            try:
                with socket.create_connection((where, 22), timeout=2):
                    break
            except OSError:
                time.sleep(2)
        else:
            print("    still not answering. It may just need another minute;\n"
                  "    if not, get in with:  virsh console %s" % VM_NAME)

        scan = sh(["ssh-keyscan", "-T", "5", "-H", where])
        if scan.stdout.strip():
            os.makedirs(os.path.expanduser("~/.ssh"), exist_ok=True)
            with open(os.path.expanduser("~/.ssh/known_hosts"), "a") as fh:
                fh.write(scan.stdout)
            print("    recorded the new host key")
    print("""
Alpine is installed.

Wait about 20 seconds, then log in:

    ssh root@%s

If that works, carry on with docs/05-router.md.
""" % where)


if __name__ == "__main__":
    main()
