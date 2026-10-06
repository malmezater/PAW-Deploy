# Why the Privileged Access Workstation (PAW) concept matters

This document explains the security model PAW-Deploy is built to support, where the tool fits in that model, and why the model is worth the operational cost. The [security README](README.md) has the diagrams, and [SECURITY-REVIEW.md](SECURITY-REVIEW.md) assesses how well the current implementation lives up to the model.

One thing up front: **PAW-Deploy does not implement tiering, and it is not a complete PAW on its own.** It makes it practical to give administrators clean, managed, disposable machines to administer from. The tiering itself is enforced by separate accounts, Conditional Access, PIM and network segmentation.

## The problem a PAW solves

Almost every serious breach of an organization's identity infrastructure follows the same shape. An administrator's everyday laptop, the one used for email, web browsing, chat and documents, is also the machine used for Domain Admin, Global Admin or hypervisor-admin sessions. That laptop is exposed to phishing, malicious attachments, drive-by downloads and compromised browser extensions every day. Once it is compromised, so is every credential and privileged session ever used on it: session tokens, cached credentials, keystrokes, clipboard contents and any admin tooling installed locally.

**If one machine with many sign-ins is compromised, every one of those accounts is compromised with it.** Move the privileged accounts off that machine, for example into a separate VM, and the same compromise no longer reaches them.

This is not hypothetical. Credential theft from a compromised admin workstation, through tools like Mimikatz, token theft or plain keylogging, is one of the most common paths to full Active Directory or tenant compromise in real incident response. Microsoft's "Securing Privileged Access" guidance treats it as the *first* problem to solve in an identity security program, ahead of MFA rollout and Conditional Access, because none of those controls help if the device doing the administering is already compromised.

There is also a quieter risk that has nothing to do with attackers: **making a change in the wrong environment.** An administrator with 40 browser tabs open across several customers or environments is one wrong tab away from changing the wrong tenant.

For consultants and MSPs the problem is sharper. The consultant's laptop is managed by the consultant's own organization, not by the customer. However well it is run, the customer cannot verify it, cannot enforce policy on it, and cannot revoke it. From the customer's point of view it is untrusted by definition.

## What a PAW actually is

A Privileged Access Workstation is a **dedicated, hardened endpoint used only for sensitive administrative tasks**, kept separate from the device used for everyday work. It is not used for email, social media or browsing. The core principle is **clean source**: *the device you connect from must be at least as trusted as what you connect to.* Privileged sessions should never run on a device that also does unprivileged, internet-facing work.

A PAW is as much a mindset as a technical setup: the goal is to **limit how far a compromise of a privileged account can spread.** Administrative platforms should never be reachable from a machine that is used for free browsing and that the organization does not really control.

The model PAW-Deploy is designed for rests on four principles:

- **Clean source.** Anything that controls an asset must be as trustworthy as the asset itself. A Domain Admin session is only as safe as the device it runs on.
- **Separate identity.** One admin account per tier (`cloud-adm`, `t0-adm`, `t1-adm`, `t2-adm`), each usable only from that tier's PAW and never from an everyday device.
- **Just-in-time privileges.** Admin roles are not standing. They are activated through PIM, time-bound and approved.
- **Device as a control.** Conditional Access only accepts a compliant, trusted device. A valid password and MFA from the wrong device is not enough.

## The chain of trust

Access to a target always follows the same chain, and each hop is only allowed from the layer before it:

```text
Everyday device  ──►  Trusted access device  ──►  PAW for the right tier  ──►  Target
```

There is no single correct way to segment or set up tiering. Every vendor and framework has its own recommendations, and the right design depends on the business and on which risks it is prepared to accept. The example below shows one way it can look.

| Tier | Covers | Example setup |
| --- | --- | --- |
| **Tier 0** – identity | Domain controllers, Entra Connect, PKI | Dedicated hardware: a separate, locked-down computer used for nothing else, and Tier 0 is never reachable from the everyday device. The drawback is carrying two computers. The alternative is Tier 0 in a VM on a heavily locked-down host that is never used for browsing; email, Teams and browsing happen in a separate VM or a Windows 365 Cloud PC. |
| **Tier 1** – servers and applications | Member servers, line-of-business applications | A managed VM, for example deployed with PAW-Deploy, that is Entra-joined and managed by Intune. No internet browsing and no software installs. It reaches Tier 1 only through an approved path, such as Global Secure Access (GSA), a VPN tunnel or a jump host / AVD. |
| **Tier 2** – clients and end-user devices | Workstations, end-user support | The same setup as Tier 1, with its own account and network rules that only allow access to Tier 2. |
| **Tier Cloud** – cloud administration | Azure, Entra, Intune, M365, Defender | Its own PAW and a separate cloud-only account (e.g. `cloud-adm`), with roles activated through PIM. **Conditional Access, not the network, decides who gets in**, so the admin portals must only be reachable from a trusted, compliant device, never directly from the everyday device. |

Tiering limits the blast radius of a compromise. An attacker who takes over a Tier 2 PAW gets end-user devices, not domain controllers.

### The reference design in the diagrams

The [diagrams](README.md#diagrams) show one concrete version of this chain for a consultant working in a customer's environment:

1. **Consultant laptop – untrusted.** Used for the consultant's own email and web. It may display the trusted access device, but it never holds customer admin credentials and cannot reach a tier PAW, admin portal or server directly.
2. **Trusted access device – customer-managed.** Entra-joined and Intune-compliant in the customer's tenant, signed into with the consultant's customer account using phishing-resistant MFA (FIDO2 or Windows Hello). No email or web browsing. Its only job is to reach the AVD gateway.
3. **Tier PAW – one per tier.** An AVD host pool per tier (Cloud, Tier 0, Tier 1, Tier 2). The consultant signs in with the tier admin account and activates the role in PIM.
4. **Target – same tier only.** Azure Firewall rules let each tier PAW reach only its own zone. A Tier 2 PAW reaches workstations but never servers or domain controllers. The Cloud PAW reaches admin portals but not the on-premises network.

The same principles apply on-premises, over RDP, through Citrix or on physical hardware. Swap the terms and the chain works the same way.

## Where PAW-Deploy fits

**PAW-Deploy is not the tiering. It is a way to deliver the trusted access device, one link in the chain.** It turns the administrator's laptop into a Hyper-V host and deploys one VM per customer or environment from a known-good golden image. How strict that VM is depends on how it is managed:

- **Managed by the customer (or by your own organization for internal work).** The *Intune OOBE* and *Domain Joined* templates enroll the VM in the customer's Entra ID and Intune, or join it to their AD. The customer then supplies the policies for how the device must look and be managed, and decides what counts as compliant. This is the PAW use case. With browsing and installs locked down by that policy, and network access limited to an approved path, the same VM can serve as the PAW for a Tier 1 or Tier 2 workload, as in the example above.
- **Workgroup VMs for quick tasks.** Sometimes you just need a machine to check or test something, or to write code and install tools and add-ons without cluttering the host. The *Windows 11 - WORKGROUP* template gives you a VM where you are local admin and can install what you need. **This is not a PAW** and should never be used for privileged access. It is still valuable, because it keeps the host clean and can be thrown away when you are done.

Both only work in practice if getting a new permanent or temporary machine is quick and easy, and that is what PAW-Deploy provides.

This follows directly from the idea that **what matters is how a device is managed, not what kind of device it is.** A VM enrolled and managed by the customer can be a trusted device even when it runs on hardware the customer does not own. The alternatives, a Windows 365 Cloud PC or a dedicated physical device per customer, fill the same role. The tier PAWs, Conditional Access, PIM and firewall rules behind it are the same whichever option is used.

What PAW-Deploy contributes to the model:

- **Admin credentials stay off the host.** Customer and tier admin accounts are only ever used inside the VMs, never on the everyday host. If the host is compromised, there are no admin accounts on it to steal.
- **Isolation between customers and environments.** Hyper-V separates the trusted environment from the host, with one VM per customer or environment, each enrolled in its own tenant. Nothing is shared between them except the host. Switching customer means switching VM, which also removes the "wrong tab" risk.
- **A known-good starting point.** Every VM starts from the same versioned Windows 11 VHDX, with the version tracked in the registry.
- **Disposable by design.** VM Destroy + Deploy gives a clean machine in minutes instead of fixing one that has drifted from its configuration. A VM that is not on the current golden image is replaced, not repaired.
- **Consistent rollout.** The installer is deployed through Intune as a Win32 app, so every laptop gets the same stages, detection and upgrades, and everyone works the same way.
- **Guest protections.** Deployed VMs get a virtual TPM with BitLocker, and deployment credentials are removed from the guest once setup is done.

## Reducing the need for local admin on the host

The VM-per-customer way of working has had a catch: creating and destroying VMs required the user to be a local administrator on their own laptop. That undermines the whole idea, since a local admin on the host is exactly the kind of standing privilege the PAW model tries to remove.

When PAW-Deploy is deployed through Intune (or ConfigMgr) with `LocalInstall = $false`, that changes:

- **VMs are created and removed through Intune.** The *Run VMDeploy* and *Remove VM* apps are started from Company Portal and run as SYSTEM, so the user does not need to be a local administrator to spin up or tear down a VM. See [Default Intune Files](../../Default%20Intune%20Files/README.md).
- **The VMDeploy files are restricted to SYSTEM.** `C:\ProgramData\VMDeploy`, which holds the VM configurations, the virtual disks and the golden image, has the Administrators and Users permissions removed, so only SYSTEM can read or change it. See [Permissions](../setup/INSTALLATION.md#permissions-intune--configmgr-only).

This lets an organization take local admin away from the user through its own Intune policy while they can still work with VMs. It does not remove every risk, and the limits should be stated plainly:

- **The user remains a member of Hyper-V Administrators.** That is required to connect to and use the VMs, and it lets the user manage VMs through Hyper-V itself. It is host-admin-equivalent in practice ([Finding 7](SECURITY-REVIEW.md)).
- **A local administrator can always take the permissions back** with `takeown.exe`. That is exactly why the point is that **the user is no longer a local administrator**: a standard user cannot reach the folder with the VM disks at all. For anyone who does hold admin rights, the restriction is friction rather than a hard boundary, and friction has value: taking ownership of that folder is a deliberate, unusual action that is far easier to detect than casual browsing.

Even if someone gets past the protections on the host, customer and internal environments are still better protected than before, because their credentials were never on the host to begin with.

## The residual risk of a VM on an untrusted host

This is the weak point of the VM approach, and it should be stated plainly. **The VM runs on a host the customer does not control, and whoever controls a hypervisor can observe its guests:** screen, keyboard input and, with enough effort, memory. The vTPM in PAW-Deploy uses a local key protector, which raises the bar for offline attacks on the VM's disk but does not protect the guest from an administrator of the running host.

The model accepts this risk because of the controls around it, not because the VM itself is immune:

- **Credentials of real value never live on the trusted device.** In the reference design, tier admin accounts are only used on the tier PAWs. The trusted device holds the consultant's customer account, protected by phishing-resistant MFA (FIDO2) that cannot be replayed from a keylogger.
- **Privileges are just-in-time.** A stolen session does not carry standing admin rights.
- **Sessions are short, and devices are disposable.** The VM can be destroyed and redeployed at any time.
- **The host is hardened and compliant.** Hyper-V remote-management firewall rules are disabled by default, the VMDeploy files are restricted to SYSTEM in Intune mode, and an optional separate local account can be created for Hyper-V administration. Such mitigations may be bypassable by a determined attacker with admin rights on the host, but the friction still matters: every extra step an attacker has to take is another chance to be detected.

If a customer's risk appetite does not allow for an MSP-managed host underneath the trusted device, a Windows 365 Cloud PC or a dedicated physical device is the better choice. The tier PAW design does not change.

## Alternatives and complements

PAW-Deploy is one option, not the only one. These can be combined depending on which risks the organization is prepared to accept:

- **Windows 365 Cloud PC** as the trusted access device (Alternative 1 in the diagrams). The laptop only shows the screen.
- **Dedicated hardware for Tier 0.**
- **A jump host or AVD host pool per tier.**
- **Global Secure Access (GSA)** as the approved network path to each tier.

## Working efficiently without giving up least privilege

A common first reaction is "this sounds like a lot of extra work." It is a different way of working, but is it really more work?

- **You change environment by changing VM.** Open the VM for a customer and you have that customer's environment. Switch VM and you have the next customer, or your internal environment. Compare that to sitting on your own laptop with 40 browser tabs open, picking the wrong one and making a change.
- **Rights are activated when needed** through PIM, instead of being permanent.
- **One image, deployed automatically.** Installation happens through Intune with the same golden image everywhere, so everyone works the same way.
- **No laptop per customer.** One host carries a VM per customer instead of a stack of devices.

## Why implementation details matter

Because PAW-Deploy provides the first trusted link in the chain, weaknesses in the tool weaken the whole model. The [security review](SECURITY-REVIEW.md) found issues that would have undone the concept in practice. For example, a guest that kept its domain-join or local Administrator password in cleartext at `C:\Windows\Panther\Unattend.xml` (Finding 2) or in the AutoLogon registry values (Finding 3) would recreate, inside the "trusted" device, exactly the standing, recoverable credential exposure the PAW model exists to eliminate. Those findings are fixed in 2.3.1.

The host-side findings matter for the same reason. Hyper-V Administrators membership (Finding 7), firewall rules for Hyper-V remoting (Finding 8) and the lack of script signing (Finding 9) are not just infrastructure concerns. In this architecture the host sits directly beneath the trusted device, and its hardening decides how large the residual risk above actually is. See the review for the current status of each.

## Why it's worth the operational friction

Separate trusted devices, separate admin accounts per tier and just-in-time activation are more overhead than using one laptop for everything. There is more to manage and more steps for admins to remember. Organizations that skip it are trading convenience against risk, and that trade tends to look very bad in hindsight, because the cost of *not* having a PAW is usually paid all at once, during an incident, rather than gradually.

The PAW model is one of the few controls that directly breaks the most common real-world attack chain (phish a user → steal cached admin credentials → take over the domain) instead of just slowing it down or detecting it afterwards. That is what makes it worth the friction. It is also why the implementation details, not just the architecture diagram, decide whether an organization actually gets that benefit or only the appearance of it.

## Background

PAW-Deploy and VMDeploy are not built from scratch. The idea of administering both customers and internal resources from Hyper-V VMs, the structure of the tooling and much of the original code come from [Mikael Nyström (DeploymentBunny)](https://github.com/DeploymentBunny), Principal Technical Architect at Truesec and long-time Microsoft MVP. The main difference in PAW-Deploy is that **Intune handles the deployment itself**, from installing Hyper-V and the tooling on the host to creating and removing VMs, which is what makes it possible to run without the user being a local administrator.
