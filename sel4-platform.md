# seL4 Platform

seL4 Platform is an operating system abstraction layer for seL4.

The seL4 microkernel provides a highly-flexible and unconstrained set of mechanisms that can be used for building systems.
While very powerful, this flexibility can make it difficult to design systems as there is a mismatch between seL4 concepts, and abstractions that are useful for building systems.

The seL4 Platform provides a much simpler and constrained set of abstractions that can be used for building certain types of systems.
A goal of providing this set of abstractions is to enable better software reuse when building systems, by enabling the creation of software components that can interact in a predictable manner.


**NOTE**: In the current drafting concepts and abstractions may be referenced prior to their description.
Please read through the entire document before providing a comment on any specific part.
Apologies, hopefully I can come up with a better structure in the future to avoid this problem.


## Terminology

As with any set of abstractions there are words that take on special meanings.
This document attempts to clearly describe all of these terms, however as the concepts and abstractions are inter-related it is sometimes necessary to use a term prior to its formal introduction.
Following is a list of the terms introduced in this document.

* core
* trust
* protection domain (PD)
* system
* static system
* dynamic system
* static protection domain
* dynamic protection domain
* protection procedure call (PPC)


## Abstractions

### Core

The seL4 Platform is designed to run on multi-core systems.

A multi-core processor is one in which there are multiple identical processing cores sharing the same L2 cache with uniform memory access.
Such a processor is usually limited to eight cores at most.

The seL4 platform is not designed for massively multi-core systems, nor systems with non-uniform memory access (NUMA).

### Protection Domain

A **protection domain** (PD) is the fundamental runtime abstraction in the seL4 platform.
It is analogous, but very different in detail, to a process on a UNIX system.

A PD provides a thread-of-control that executes within a fixed virtual memory space, with a fixed set of capabilities.

The PD operates at a fixed priority on a specific CPU core.

A PD *may* provide a *protected procedure* that can be called from other PDs.
Note: The protected procedure always executes on the caller PDs core, but with the priority of the callee's PD.

A protection domain has three entry points:

* initialisation
* notification handler
* protected procedure

The initialisation entry point is called only once.
The notification handler and protected procedure handler entry points are called multiple times.
Entry points do *not* run concurrently.

Initialisation runs on a special, one-time, start-up scheduler context.
Notification handler run on the PDs configured scheduler context (which includes the core on which these run).
Protected procedures run on the caller's scheduler context (which may mean protected procedure run on a different core to the notification handler).

There is a very narrow set of platform functions that can be accessed by the entry points:

* performing a protected procedure call
* notifying another protection domain

(In both cases with appropriate access control enforced by seL4 capabilities).


### Communication Channels

Protection domains can communicate (for both control and data exchange purposes) via *communication channels*.

Communication is always considered to be two-way from an information flow point of view; there is no concept of one-way communication between protection domains.

Communication between two PDs does **not** imply a specific trust relationship between the two PDs.

A communication channel between two PDs provides the following:

* Ability for each PD to notify the other PD.
* Region of read-write memory shared between the two PDs.
* Ability for one PD to make protected procedure calls to the other PD [note: this is optional, and *does* imply a trust relationship].

The communication relationships between protection domains can be expressed as a non-directed cyclic graph.


#### Protected Procedure

A protected procedure call (PPC) enables a *caller* protection domain to call a *protected procedure* residing in the *callee* protection domain.

The caller PD must trust the callee PD.

*Note:* A PD can have at most one protected procedure.
Different functionality can be dispatched based on the arguments passed to the protected procedure.

In a static system the protected procedure call graph can be determined statically, which shall allow some form of static analysis of the system.

The protected procedure call graph *must not contain loops*.
I.e.: It is not valid that have PD *A* calling PD *B*, which in turns calls PD *A*.
It is an error to construct a system that contains loop (such an error should be determined at construction time in a static system; in a dynamic system managers must ensure changes to the system do not introduce loops).

It is allowed for a protected procedure to make a PPC as long as it does not cause a loop.
For example, PD *A* can call PD *B*, which in turn calls PD *C* as part of protected procedure.

A protected procedure call can only be made in cases where the callee PD has a priority equal to or higher than the caller PD.

The protected procedure implementation in the callee PD *must not block*.
Ideally, this should be analyzed and confirmed as part of the system build / analysis tools.
An outcome of this is that, clearly, a callee PD is only servicing one callee at a time [assuming single core, on multi-core this is extended to one callee per core].

It is expected that there may be different specific functionality implemented by a server protection domain.
The arguments passed in the PPC to the protection domain must be used appropriately by the server protection domain to interpret the behaviour requested by the caller PD.

The arguments passed in a PPC is limited to 64 machine words.
This is not dissimilar to the limitation on the number/size of arguments that may be passed using the C ABI on any specific platform.
There are not many services that can be provided where passing 64 machine words is sufficient or appropriate.
The following section describes how memory is shared between protection domains for handling data transfer.

The callee is provided with the (non-forgable) identify of the caller protection domain.
The server protection domain must use the caller identity to perform any appropriate access control.

#### Shared Memory

A communication channel between two protection domains includes a single region of shared memory.
The memory is shared a read-write (no-execute) permission in both protection domains.

The region size can be an arbitrary number of pages, but must be mapped into contiguous virtual memory.
The virtual memory region need not be the same in each PD.
[Note: we may want to restrict to power-of-two to allow fast offset verification.]

In the case of PPC the server PD maintains a mapping from callee identity (badge) to the virtual memory.

Raw pointers are *never* passed as arguments (or return values) of the PPC.
Instead offset into the shared memory region is passed.
[Note: There are possibly neat implementation tricks to make this fast especially is the region is sufficiently aligned].

The format of the shared memory is not (currently) defined.
It is expected as this platform specification evolves at least some areas of the shared memory region will be specified.


#### Notifications

A notification is a way that one PD can indicate (to the other PD) that there is work to be done.

On receiving a notification a PD can identify which PD has provided the notification. [Note: An alternative is that a notification can identify a 'set' of PDs, which at least one has work todo. Need iff not enough bits in the badge.]

A notification is *just* an interrupt and does not have a payload (above identifying to other PD).

On receiving a notification the PD examines the shared memory to identify the work to do.
The exact format of the shared memory region is not currently defined.


## System construction concepts

This section introduces some other concepts related to building systems.

### Trust

Trust is a multi-faceted concept that can have many areas of nuance.
A pure seL4 system allows for the construction of systems with complex trust relationships.

For the seL4 platform it is recognized that a set of complex trust relationships leads to difficulties in understanding (from a human or machine point of view) the overall security posture of the system.
For this reason within an seL4 Platform system trust *between protection domains* is limited to a binary relationship.
A given protection domain may either trust or not trust another protection domain.
The trust relationship is one-way only.
To say that PD **A** trusts PD **B** does not imply that PD **B** trusts PD **A**.

Although limited in full expression this still provides a richer description of trusted than simply labelling protection domains as *trusted* and *untrusted* overall.

The default state of any trust relationship is *does not trust*.
For a given system a directed graph can be used to express the trust relationships of the protection domains.

An important part of system construction is that these trust relationships must be made explicit by the system designer.

Forcing the system designer to explicitly label the trust relationships between protection domains allows for static analysis (for example, that a PD does not make a PPC to a protection domain that it does not trust).


### Static system

A static system is one where the protection domains that make up the system are defined at system build time.
A static system may be composed of dynamic protection domains! (Although in most cases, most protection domains would be static).

### Dynamic system

A dynamic system has one (or potentially more) protection domains which are capable of creating new protection domains at run-time, and of managing the cspace of other protection domains.

A dynamic system may be composed of both static and dynamic protection domains.



## Implementation


### Protected procedure calls

The PPC mechanism abstracts over seL4 IPC.

Specifically, a PPC call uses *seL4_CallWait* system call.
The callers scheduling context is transferred to the callee.
The callee performs all work on the scheduling context.
If the scheduling context does not provide sufficient CPU resources, then [FIXME: detail needed here, can be an error, can require server to context switch the TCB back to waiting on something else.]

The server protection domain has a TCB (without a scheduling context?) waiting on an endpoint using **seL4_Wait** and/or **seL4_ReplyWait**.

Badges are used to identify each caller.
The maximum number of callers is limited by the badge address space.
