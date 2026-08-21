# Why the Privileged Access Workstation (PAW) concept matters

This document explains the security model PAW-Deploy is built to implement,
and why that model is worth the operational cost. It's meant to be read
alongside [SECURITY-REVIEW.md](SECURITY-REVIEW.md), which assesses how well
the current implementation lives up to it.

## The problem a PAW solves

Almost every serious breach of an organization's identity infrastructure
follows the same shape: an administrator's everyday laptop — the one used
for email, web browsing, chat, and document editing — is also the machine
used to run Domain Admin, Global Admin, or Hyper-V/hypervisor-admin sessions.
That laptop is exposed to phishing, malicious attachments, drive-by
downloads, and compromised browser extensions every single day. The moment
it's compromised, so is every credential and every privileged session ever
used on it — session tokens, cached credentials, keystrokes, clipboard
contents, and any admin tooling installed locally.

This is not a hypothetical: credential theft from a compromised admin
workstation (via tools like Mimikatz, token theft, or simple keylogging) is
one of the most common paths to full Active Directory or tenant compromise
in real-world incident response. Microsoft's own guidance (the "Securing
Privileged Access" roadmap) treats this as the *first* problem to solve in
any identity security program — ahead of MFA rollout, ahead of conditional
access policy, ahead of most other controls — because none of those controls
matter if the endpoint doing the administering is already compromised.

## What a PAW actually is

A Privileged Access Workstation is a **dedicated, hardened endpoint used
exclusively for sensitive administrative tasks**, kept separate from the
device used for general productivity. The core principle is simple:
**privileged sessions should never run on a device that also does
unprivileged, internet-facing work.**

In practice this means:

- **Isolation of blast radius.** If the day-to-day laptop is compromised via
  phishing, the attacker gets that user's mailbox and files — not Domain
  Admin. If the PAW is compromised, it's because someone specifically
  targeted the hardened, tightly-controlled admin path, which is a much
  higher bar to clear.
- **A minimized, deliberately controlled attack surface.** No general web
  browsing, no personal email, no arbitrary software installs, tightly
  scoped firewall rules, and no unnecessary listening services — every
  reduction in what *can* run on the box is a reduction in what an attacker
  can use.
- **Strong local protections by default.** BitLocker/TPM-backed disk
  encryption, no persisted plaintext credentials, and (where virtualization
  is used to provision guest sessions, as in this project) VM-level
  protections like Shielded VMs so that even the hypervisor operator can't
  trivially extract secrets from a guest's memory or disk.
- **Credential separation.** Privileged accounts are used *only* from the
  PAW, never from a standard workstation, and ideally never persist on disk
  in recoverable form anywhere — not in config files, not in setup
  artifacts, not in temp files.

## Why this project chose Hyper-V VMs, not a bare metal PAW

PAW-Deploy implements the PAW model by turning a Windows 11 host into a
Hyper-V host and provisioning short-lived, purpose-built guest VMs for admin
work (`VMDeploy`), rather than hardening the host itself as the direct admin
surface. This is a legitimate and common pattern — it adds a hypervisor
isolation boundary between the physical hardware/host OS and the actual
privileged session, and it makes "give me a clean admin box" a
few-minutes operation instead of a re-image. The trade-off is that the
**guest VM now carries the same responsibility a bare-metal PAW would**:
whatever credential hygiene, disk encryption, and hardening a PAW needs, the
guest needs it too — and the *host* now needs its own hardening on top,
since compromise of the Hyper-V host compromises every guest it's running.

That's precisely why the credential-persistence issues in
[SECURITY-REVIEW.md](SECURITY-REVIEW.md) (Findings 2 and 3) matter more here
than they might in a generic VM-provisioning tool: the entire reason this
tool exists is to give administrators a place to use their highest-value
credentials safely. A guest VM that leaves the Domain Admin password used to
join it sitting in cleartext at `C:\Windows\Panther\Unattend.xml` has
recreated, inside the "safe" PAW guest, exactly the kind of standing,
recoverable credential exposure the PAW model exists to eliminate. Likewise,
the host hardening findings (widened firewall rules, standing Hyper-V
Administrators membership, no script signing) matter because the *host* in
this architecture is not just infrastructure — it is, in effect, part of the
PAW's own trusted computing base.

## Why it's worth the operational friction

Maintaining a separate admin device (or, as here, a separate admin VM
workflow) is more overhead than just using one laptop for everything. Extra
hardware or VM management, extra process for admins to remember to switch
context, extra tooling to keep updated. Organizations that skip it are
making a deliberate trade of convenience against risk — and that trade tends
to look very bad in hindsight, because the cost of *not* having a PAW is
usually paid all at once, during an incident, rather than gradually.

The PAW model is one of the few controls that directly breaks the most
common real-world attack chain (phishing a user → stealing cached admin
credentials → domain-wide compromise) rather than just slowing it down or
detecting it after the fact. That's what makes it worth the friction, and
it's why the implementation details — not just the architecture diagram —
determine whether an organization actually gets that benefit or only the
appearance of it.
