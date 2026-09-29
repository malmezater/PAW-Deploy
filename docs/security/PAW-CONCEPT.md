# Why the Privileged Access Workstation (PAW) concept matters

This document explains the security model PAW-Deploy is built to support, where the tool fits in that model, and why the model is worth the operational cost. The [security README](README.md) has the diagrams, and [SECURITY-REVIEW.md](SECURITY-REVIEW.md) assesses how well the current implementation lives up to the model.

## The problem a PAW solves

Almost every serious breach of an organization's identity infrastructure follows the same shape. An administrator's everyday laptop, the one used for email, web browsing, chat and documents, is also the machine used for Domain Admin, Global Admin or hypervisor-admin sessions. That laptop is exposed to phishing, malicious attachments, drive-by downloads and compromised browser extensions every day. Once it is compromised, so is every credential and privileged session ever used on it: session tokens, cached credentials, keystrokes, clipboard contents and any admin tooling installed locally.

This is not hypothetical. Credential theft from a compromised admin workstation, through tools like Mimikatz, token theft or plain keylogging, is one of the most common paths to full Active Directory or tenant compromise in real incident response. Microsoft's "Securing Privileged Access" guidance treats it as the *first* problem to solve in an identity security program, ahead of MFA rollout and Conditional Access, because none of those controls help if the device doing the administering is already compromised.

For consultants and MSPs the problem is sharper. The consultant's laptop is managed by the consultant's own organization, not by the customer. However well it is run, the customer cannot verify it, cannot enforce policy on it, and cannot revoke it. From the customer's point of view it is untrusted by definition.

## What a PAW actually is

A Privileged Access Workstation is a **dedicated, hardened endpoint used only for sensitive administrative tasks**, kept separate from the device used for everyday work. The core principle is **clean source**: *the device you connect from must be at least as trusted as what you connect to.* Privileged sessions should never run on a device that also does unprivileged, internet-facing work.

The model PAW-Deploy is designed for rests on four principles:

- **Clean source.** Anything that controls an asset must be as trustworthy as the asset itself. A Domain Admin session is only as safe as the device it runs on.
- **Separate identity.** One admin account per tier (`cloud-adm`, `t0-adm`, `t1-adm`, `t2-adm`), each usable only from that tier's PAW and never from an everyday device.
- **Just-in-time privileges.** Admin roles are not standing. They are activated through PIM, time-bound and approved.
- **Device as a control.** Conditional Access only accepts the customer's own compliant, trusted device. A valid password and MFA from the wrong device is not enough.

## The chain of trust

Access to a target always follows the same chain, and each hop is only allowed from the layer before it:

1. **Consultant laptop – untrusted.** Used for the consultant's own email and web. It may display the trusted access device, but it never holds customer admin credentials and cannot reach a tier PAW, admin portal or server directly.
2. **Trusted access device – customer-managed.** Entra-joined and Intune-compliant in the customer's tenant, signed into with the consultant's customer account using phishing-resistant MFA (FIDO2 or Windows Hello). No email or web browsing. Its only job is to reach the AVD gateway.
3. **Tier PAW – one per tier.** An AVD host pool per tier (Cloud, Tier 0, Tier 1, Tier 2). The consultant signs in with the tier admin account and activates the role in PIM.
4. **Target – same tier only.** Azure Firewall rules let each tier PAW reach only its own zone. A Tier 2 PAW reaches workstations but never servers or domain controllers. The Cloud PAW reaches admin portals but not the on-premises network.

Tiering limits the blast radius of a compromise. An attacker who takes over a Tier 2 PAW gets end-user devices, not domain controllers.

## Where PAW-Deploy fits

**PAW-Deploy delivers the trusted access device (step 2). It does not build the tier PAWs.** It turns the consultant's laptop into a Hyper-V host and deploys one VM per customer from a known-good golden image. Each VM is then enrolled in that customer's Entra ID and Intune, so the customer, not the consultant, decides what counts as compliant.

This follows directly from the idea that **what matters is how a device is managed, not what kind of device it is.** A VM enrolled and managed by the customer can be a trusted device even when it runs on hardware the customer does not own. The alternatives, a Windows 365 Cloud PC or a dedicated physical device per customer, fill the same role. The tier PAWs, Conditional Access, PIM and firewall rules behind it are identical whichever option is used.

What PAW-Deploy contributes to the model:

- **A known-good starting point.** Every VM starts from the same versioned Windows 11 VHDX, with the version tracked in the registry.
- **Disposable by design.** VM Destroy + Deploy gives a clean machine in minutes instead of patching one that has drifted. A VM that is not on the current golden image is replaced, not repaired.
- **Isolation between customers.** One VM per customer, each enrolled in its own tenant. Nothing is shared between customer environments except the host.
- **Consistent rollout.** The installer is deployed through the MSP's Intune as a Win32 app, so every consultant laptop gets the same stages, detection and upgrades.
- **Guest protections.** Deployed VMs get a virtual TPM with BitLocker, and deployment credentials are removed from the guest once setup is done.

## The residual risk of a VM on an untrusted host

This is the weak point of the VM approach, and it should be stated plainly. **The VM runs on a host the customer does not control, and whoever controls a hypervisor can observe its guests:** screen, keyboard input and, with enough effort, memory. The vTPM in PAW-Deploy uses a local key protector, which raises the bar for offline attacks on the VM's disk but does not protect the guest from an administrator of the running host.

The model accepts this risk because of the controls around it, not because the VM itself is immune:

- **Credentials of real value never live on the trusted device.** Tier admin accounts are only used on the tier PAWs. The trusted device holds the consultant's customer account, protected by phishing-resistant MFA that cannot be replayed from a keylogger.
- **Privileges are just-in-time.** A stolen session on the trusted device does not carry standing admin rights.
- **Sessions are short, and devices are disposable.** The VM can be destroyed and redeployed at any time.
- **The host is hardened.** Hyper-V remote-management firewall rules are disabled by default, and an optional separate local account can be created for Hyper-V administration. Such mitigations may be bypassable by a determined attacker with admin rights on the host, but the friction still matters: every extra step an attacker has to take is another chance to be detected.

If a customer's risk appetite does not allow for an MSP-managed host underneath the trusted device, Alternative 1 (Cloud PC) or a dedicated physical device is the better choice. The tier PAW design does not change.

## Why implementation details matter

Because PAW-Deploy provides the first trusted link in the chain, weaknesses in the tool weaken the whole model. The [security review](SECURITY-REVIEW.md) found issues that would have undone the concept in practice. For example, a guest that kept its domain-join or local Administrator password in cleartext at `C:\Windows\Panther\Unattend.xml` (Finding 2) or in the AutoLogon registry values (Finding 3) would recreate, inside the "trusted" device, exactly the standing, recoverable credential exposure the PAW model exists to eliminate. Those findings are fixed in 2.3.1.

The host-side findings matter for the same reason. Hyper-V Administrators membership (Finding 7), firewall rules for Hyper-V remoting (Finding 8) and the lack of script signing (Finding 9) are not just infrastructure concerns. In this architecture the host sits directly beneath the trusted device, and its hardening decides how large the residual risk above actually is. See the review for the current status of each.

## Why it's worth the operational friction

Separate trusted devices, separate admin accounts per tier and just-in-time activation are more overhead than using one laptop for everything. There is more to manage and more steps for admins to remember. Organizations that skip it are trading convenience against risk, and that trade tends to look very bad in hindsight, because the cost of *not* having a PAW is usually paid all at once, during an incident, rather than gradually.

The PAW model is one of the few controls that directly breaks the most common real-world attack chain (phish a user → steal cached admin credentials → take over the domain) instead of just slowing it down or detecting it afterwards. That is what makes it worth the friction. It is also why the implementation details, not just the architecture diagram, decide whether an organization actually gets that benefit or only the appearance of it.
