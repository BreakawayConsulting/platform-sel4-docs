% The seL4 Core Platform
% Benno, Gernot
% Draft of \today

The seL4 Core Platform is an operating system (OS) personality for the seL4
microkernel.

# Purpose of the platform

* Provide a small and simple OS for a wide range of IoT, cyberphysical
and other embedded use cases;
* provide a reasonable degree of application portability appropriate
for the targeted use cases;
* make seL4-based systems easy to develop and deploy within the target areas;
* provide well-defined hardware interfaces to ease porting of the
Platform;
* support a high degree of code reuse between deployments;
* provide well-defined internal interfaces to support diverse
  implementations of the same logical service to adapt to
usage-specific trade-offs and ease compatibility between
implementation of system services from different developers;
* have an architecture that leverages seL4's strong isolation
properties to support a near-minimal *trusted computing base* (TCB);
* be, in principle, amenable to formal analysis of system safety and
  security properties (although such analysis is beyond the initial scope).

# Rationale

The seL4 microkernel provides a set of powerful and flexible
mechanisms that can be used for building almost arbitrary systems.
While minimising constraints on the nature of system designs and scope
of deployments, this flexibility makes it challenging to design the
best system for a particular use case, requiring extensive seL4 experience
from developers.

The seL4 Core Platform addresses this challenge by constraining the
system architecture and to one that provides enough features and power
for this usage class, enabling a much simpler set of developer-visible
abstractions.

# Terminology

As with any set of abstractions there are words that take on special meanings.
This document attempts to clearly describe all of these terms, however
as the concepts and abstractions are inter-related it is sometimes
necessary to use a term prior to its formal introduction.

Following is a list of the terms introduced in this document.

* processor core (core)
* protection domain (PD)
* communication channel (CC)
* memory region
* notification
* protected procedure call (PPC)

As these abstractions are built on seL4 abstractions, their
explanations need to refer to the seL4 terms (in *italics*). This will help readers
familiar with the seL4 abstractions to understand the
correspondence. However, the intention of this document is that it can
be mostly understood without a knowledge of the underlying seL4
abstractions, so the reader with little seL4 background can safely
skip references to underlying seL4 constructs.

However, the [seL4 Whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf) is recommended background information for
this document.

# Abstractions

## Core

The seL4 Core Platform is designed to run on multi-core systems.

For the purpose of this document,
a multi-core processor is one in which there are multiple identical
processor cores (cores) sharing the same L2 cache with uniform memory access.
Such a processor is usually limited to no more than eight cores.

The seL4 Core Platform is not designed for massively multi-core
systems, nor systems with non-uniform memory access (NUMA).

**Rationale**

> In large multicore processors many design trade-offs change, trying
> to support them would introduce unwarranted complexity into the
> platform, as such processors are presently uncommon in the target domains.

## Protection Domain

A **protection domain** (PD) is the fundamental runtime abstraction in the seL4 platform.
It is analogous, but very different in detail, to a process on a UNIX system.

A PD provides a thread of control that executes within a fixed seL4
*virtual address space*, with a fixed set of seL4 *capabilities* that enable access to a limited set of seL4-managed resources.

The PD operates at a fixed seL4 *priority* level.
Each PD has an associated seL4 *scheduling context*.
The seL4 scheduling objects controls which core the protection domain normally executes on.

When an seL4 Core Platform system is booted, all protection domains in the system execute an *initialisation* procedure.
The initialisation procedure runs using the PD's seL4 scheduling object.

After the initialisation procedure is complete, the protection domain's *notification* procedure will be invoked whenever the protection domain receives a *notification*.
The notification procedure also runs using the PD's seL4 scheduling context.
The notification procedure will not run at the same time as the initialisation procedure, and will never be called in parallel (i.e. there is only a single instance of the notification procedure running at any point in time).

In addition to the initialisation and notification procedures a
protection domain *optionally* provide a *protected* procedure.
The *protected* procedure is one that can be called from a different protection domain.
When the protected procedure is called, it executes at the PD's
priority, but will use the **callers** seL4 scheduling object, and
therefore on the caller's core.
A consequence of this is that the protected procedure may run on a different core to that on which the initialisation and notification procedures run.
The protected procedure will not run in parallel with either the
initialisation or the notification procedures, so there is no need for
concurrency control within a PD.

There is a small set of seL4 platform APIs that a protection domain may make use of (from any type of procedure).
These are:

* call a protected procedure in a different protection domain
* send a notification to a different protection domain.

These calls are only possible in the case where a *communication
channel* is established between the PDs.

**Rationale**

> PDs are single-threaded to keep the programming model and
> implementations simple, and because this serves the needs of most
> present use cases in the target domains. Extending the model to
> multithreaded applications (clients) is straightforward and an be
> done if needed. Extending to multithreaded services is possible but
> requires additional infrastructure for which we see no need in the
> near future.

## Memory regions

A memory region is a range of physical memory.
A memory region must be at least page size.
The size of a memory region my by a power-of-2.
The base address of a memory region must be aligned to its size.

Each memory region can be mapped into a protection domain.
The mapping attributes include:

* virtual address space
* caching attributes
* permissions attributes

It is valid that a memory region may be mapped into a protection domain multiple times (for example, with different caching attributes).

A memory region can be mapped into multiple different protection domains.
The virtual address can be different in each protection domain.

In addition to mapping a memory region into a protection domain, a memory region may also be *attached* to a communication channel.
An attached communication channel enables memory pointers to objects within the memory region to be safely shared between protection domains.
Normally, a memory region that is attached to a communication channel would also be mapping into both protection domains, however there are some cases in which a memory region is attached to the communication channel *without* also being mapping into both protection domains.


## Communication Channels

Protection domains can communicate (for both control and data exchange purposes) via *communication channels*.

Communication is always considered to be two-way from an information flow point of view; there is no concept of one-way communication between protection domains.

Communication between two PDs does **not** necessarily imply a specific trust relationship between the two PDs.

A communication channel between two PDs provides the following:

* Ability for each PD to notify the other PD.
* Ability to reference memory regions associated with the communication channel.
* Ability for one PD to make protected procedure calls to the other PD [note: this is optional, and *does* imply a trust relationship].

The communication relationships between protection domains can be expressed as a non-directed cyclic graph.


### Protected Procedure

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

### Shared Memory

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


### Notifications

A notification is a way that one PD can indicate (to the other PD) that there is work to be done.

On receiving a notification a PD can identify which PD has provided the notification. [Note: An alternative is that a notification can identify a 'set' of PDs, which at least one has work todo. Need iff not enough bits in the badge.]

A notification is *just* an interrupt and does not have a payload (above identifying to other PD).

On receiving a notification the PD examines the shared memory to identify the work to do.
The exact format of the shared memory region is not currently defined.


# Runtime API

## Types

`Channel` is an opaque reference to a specific channel.
This type is used extensively through-out the functional API.

`Memptr` is an opaque reference to a pointer.
Memptr can be decoded into specific pointers.

## Entry Points

### `void init(void)`

Every protection must expose an init function.
This is called by the system when the protection domain is created.
The `init` function executes using the protection domain's scheduling context.

### `void notified(Channel channel)`

The `notified` entry point is called by the system when the protection domain has received a notification via a communication channel.
A channel identifier is passed to the function indicating which specific channel was notified.


### `void protected(Channel channel)`

The `protected` entry point is optional.
The `protected` entry point is called by the system when another PD makes a protected call to the PD via a channel.
The caller is identified via the `channel` parameter.

The parameters passed by the caller may be accessed via **FIXME**.
Any return values should be set via **FIXME**.

When the `protected` entry point returns, the protected procedure call completes.


## Functions

### `void notify(Channel channel)`

Send a notification to a specific channel.

### `void ppcall(Channel channel)`

Perform a protected-procedure call to a specified channel.
Any parameters should be set via **FIXME**.

### `Memptr memptr_encode(Channel channel, ....)`

Encode a pointer to a memory address.

### `void * memptr_decode(Channel channel, Memptr memptr)`

Decode the `memptr` to a pointer.

**FIXME:** If this is a bad ptr, how is that handled? Return null or exception?

### `Dmaptr memptr_decode(Channel channel, Memptr memptr)`

Decode the `memptr` to a DMA address
This is used to convert `memptr` to values that can be used by bus masters.

**FIXME:** Handling of bad ptrs, also likely need a DMA context of some description for cases when there is I/O MMU.


### `Memptr memptr_transcode(Channel from_channel, Memptr memptr, Channel to_channel)`

Directly decode/encode a `memptr` associated with `from_channel` to a memptr associated with `to_channel`.

### Setting IPC buffers

**FIXME**: Need to have APIs for setting the IPC buffer.

### Cache operations

**FIXME**: Need to have APIs for performing cache flushes, etc.


# System construction concepts

This section introduces some other concepts related to building systems.

## Trust

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


## Static system

A static system is one where the protection domains that make up the system are defined at system build time.
A static system may be composed of dynamic protection domains! (Although in most cases, most protection domains would be static).

## Dynamic system

A dynamic system has one (or potentially more) protection domains which are capable of creating new protection domains at run-time, and of managing the cspace of other protection domains.

A dynamic system may be composed of both static and dynamic protection domains.



# Implementation


## Protected procedure calls

The PPC mechanism abstracts over seL4 IPC.

Specifically, a PPC call uses *seL4_CallWait* system call.
The callers scheduling context is transferred to the callee.
The callee performs all work on the scheduling context.
If the scheduling context does not provide sufficient CPU resources, then [FIXME: detail needed here, can be an error, can require server to context switch the TCB back to waiting on something else.]

The server protection domain has a TCB (without a scheduling context?) waiting on an endpoint using **seL4_Wait** and/or **seL4_ReplyWait**.

Badges are used to identify each caller.
The maximum number of callers is limited by the badge address space.
