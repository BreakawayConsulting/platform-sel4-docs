% The seL4 Core Platform
% Benno, Gernot
% Draft of \today
<!--
	Use the above to set title, author and date.
	First use of seL4 must have registered trademark sign, as above.
	Date is optional; if no date is given, author(s) is optional.
-->

<!--
	Copyright 2020, Ben Leslie, Gernot Heiser
	SPDX-License-Identifier: CC-BY-SA-4.0
-->

\doCopyright[2020]
<!--
	Keep the above command at the top to produce the copyright note,
	the argument is the copyright year; if omitted (incl brackets),
	it defaults to the year of build.
-->

The *seL4 Core Platform* is an operating system (OS)
personality for the seL4 microkernel.

# Purpose

The seL4 Core Platform is to:

* provide a small and simple OS for a wide range of IoT, cyberphysical
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
* leverage seL4's strong isolation
properties to support a near-minimal *trusted computing base* (TCB);
* retain seL4's trademark performance for systems built with it;
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

# The seL4 Core Platform is Not Posix compatible

**Rationale**

> The Unix model is now [over half a century
old](https://link.springer.com/content/pdf/10.1007%2F3-540-09745-7_2.pdf). It
> was great when it was created, it started getting a bit dated by the
> time it became standardised as Posix in 1988, and it is really not
> longer the right model. Hence, we specifically do *not* aim to be
> Posix compatible, and instead try to come up with what is best for
> seL4 and its use cases.

## Can you be more specific?

Posix has many things that made sense on a 1969-vintage PDP-7 or
PDP-11, but are not the right approach today. This includes:

Posix has a global name space

: This is nice for easily locating and referencing objects. It has the
distasteful side effect of introducing covert storage channels. Not a
good match for seL4, which is designed to be highly secure and
*proved* to be free of storage channels.

Posix uses copying I/O interfaces

: Posix treats everything as a file, and the interfaces are read/write
by copying things to and from argument buffers. This is not a good
model for a high-performance system, and seL4 is designed for high
performance. I/O interfaces should be zero-copy.

Posix is heavyweight

: Posix threads and process are expensive to create and use, orders of
magnitude more than the seL4 equivalents. For example, we measured on an
Intel Skylake platform that creating and deleting a Pthread costs over
500\ µs, while signal/wait and context switch takes over 50\ µs. In
contrast, switching between seL4 threads (eg via IPC) is about 0.1\ µs!
<!-- Pthreads:
https://bitbucket.ts.data61.csiro.au/users/pchubb/repos/pthreadsbench/browse -->

: Of course, Posix threads do much more than seL4 threads, but
most of the time you don't need this extra functionality (and
weight). Let's allow seL4-based systems to remain slim!

fork() was cool 50 years ago on a PDP-11

: but it's very uncool today:
["We catalog the ways in which fork is a terrible abstraction for the modern programmer to use."](https://dl.acm.org/doi/pdf/10.1145/3317550.3321435)
'Nuff said.

## So, how do I run my legacy software?

The initial intended use cases considered are those for which
new software is being written to take advantage of the features
provided by seL4 and the seL4 Core Platform.

Future versions of the seL4 Core Platform intend to provide a
[virtual machines](#vm) abstraction that allows running legacy
software within a Linux operating system.

# Terminology

As with any set of abstractions there are words that take on special meanings.
This document attempts to clearly describe all of these terms, however
as the concepts and abstractions are inter-related it is sometimes
necessary to use a term prior to its formal introduction.

Following is a list of the terms introduced in this document.

* [processor core (core)](#core)
* [protection domain (PD)](#pd)
* [communication channel (CC)](#cc)
* [memory region](#region)
* attached memory region
* memory reference
* [notification](#notification)
* [protected procedure](#pp)
* [virtual machine (VM)](#vm)
* client
* server

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

## Processor Core ## {#core}

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

## Protection Domain {#pd}

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
priority, but will use the **caller's** seL4 scheduling object, and
therefore on the caller's core.
A consequence of this is that the protected procedure may run on a different core to that on which the initialisation and notification procedures run.
The protected procedure will not run in parallel with either the
initialisation or the notification procedures, so there is no need for
concurrency control within a PD.

There is a small set of seL4 Core Platform APIs that a protection domain may make use of (from any type of procedure).
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

## Memory regions {#region}

A memory region is a contiguous range of physical memory.
The size of a memory region must be a multiple of a supported page size.

A memory region may be mapped into a protection domain.
The mapping has a number of attributes, which include:

* the virtual address at which the region is mapped in the PD
* caching attributes (mostly relevant for device memory)
* permissions (full access, R/O, X/O).

A memory region may be mapped into multiple PDs; the mapping addresses
for each PD may be different. A memory region can also be mapped
multiple times into the same PD (for example, with different caching
attributes). Mappings (of the same or different regions) must not overlap.

A memory region may also be *attached* to a communication channel (see
below), irrespective of whether the region is mapped into any PD or not.

When a memory region is attached to a communication channel it provides
a mechanism for communication channels to refer to data structures within
the region in a safe manner.

## Communication Channels {#cc}

Protection domains can communicate (exchanging data, control or both)
via *communication channels*. Each channel connects exactly two PDs;
there are no multi-party channels. Each pair of PDs can have at most
one communication channel.

Communication through channels may be uni- or bi-directional in terms
of data movement, but is always bi-directional in terms of information
flow: due to synchronisation, channels cannot
prevent information flowing both ways.

Communication between two PDs does in general **not** imply a specific trust relationship between the two PDs.

The overall communications within the system form a non-directed, cyclic graph with protection domains as the nodes and communication channels as the edges.

A communication channel between two PDs provides the following:

* Ability for each PD to *notify* the other PD.
* Ability to reference memory within a memory region attached to the communication channel.
* Optionally, the ability to make protected procedure calls from one PD to the other.

Each of these is defined in more detail in the following sections.

### Notifications ### {#notification}

A notification is a semaphore-like synchronisation mechanism. A PD can
signal another PD's notification to indicate availability of data in
an attached memory region. The notification transfers the signalling
PD's unforgeable identity. There is no payload associated with a
notification.

**Note**

> Details of the notification protocol are not presently defined
> by the seL4 Core Platform.

Depending on the assignment of priorities and cores to PDs, a PD's
notification may be signalled multiple times (by different clients)
before the PD can start processing them. The receiving PD can identify
the different clients and process all requests. However, if a client
signals the same PD multiple times before that PD gets to process the
notification, it will only receive it once (it behaves as a binary
semaphore).

**Note**

> The number of unique notifiers per PD is limited to the number
> of bits in a machine word by the underlying seL4 Notification
> mechanism. This is expected to be sufficient for the
> target application domains of the seL4 Core Platform. Should the
> number of notifiers exceed this limit, a more complex protocol will
> need to be specified that allows disambiguating a larger number of notifiers.

### Attached Memory Region

Memory regions may be attached to a communication channel.
It is possible for multiple memory regions to be attached to a communication channel.

Attached memory regions provided a way for the PD utilizing the communication channel to refer to a specific memory location.
A memory reference is an efficient encoding that identifies a specific offset within an attached memory region.

Normally an attached memory region will be mapped into both protection domains, however it is likely that the memory region will be mapped at different virtual address in each PD.
Additionally, it could be mapped with different permissions.
For example, it may be read-write in one PD, while read-only in the other.
When an attached memory region is mapped into a PD the Platform provides suitable functions for converting between a pointer and a memory reference.

It is important to note that raw pointers to virtual-memory addresses should never be passed between protection domains.

A memory reference is specific to a given communication channel.
Alternatively, a protection domain can use a memory reference to create a new memory reference that is valid for a different communication channel (assuming that the memory region

**Note**

> The seL4 Core Platform does not presently impose a structure
> on a channel-attached memory region. We expect that future versions of
> the specification will specify semantics for part of the shared region (headers).

### Protected Procedures {#pp}

A protected procedure call (PPC) enables the caller PD to invoke a
*protected procedure* residing in the callee PD.
A PD that provides a protected procedure is referred to as a *server* PD.
A PD that calls a protected procedure is referred to as a *client* PD.

Transitive calls are possible, and as such a PD may be both a *client* and a *server*.
However the overall relationship between clients and server forms a directed, acyclic graph.
It follows that a PD can not call itself, even indirectly.
For example, `A calls B calls C` is valid, while `A calls B calls A` is not valid.

A PD can have at most one protected procedure. Arguments ("opcode") passed through the call can be used to choose from different functionalities the callee
may provide, according to a callee-defined protocol.

The seL4 Core Platform provides a *static architecture*, where all PDs
are determined at system build time. In such a system, the PPC call
graph can be statically determined, which supports determining certain
security and safety properties by static analysis.

The callee of a PPC must have a strictly higher priority than the
caller. This property is statically enforceable from the acyclic call
graph, and build tool should enforce this property.

**Rationale**

> This rule of only calling to higher priority prevents deadlocks and
> reflects the notion that the callee operates on behalf of the
> caller, and it should not be possible to preempt execution of the
> callee unless the caller could be preempted as well. This greatly
> simplifies reasoning about real-time properties in the system; in
> particular, it means that PPCs can be used to implement *resource
> servers*, where shared resources are encapsulated in a component
> that ensures mutual exclusion, while avoiding unbounded priority
> inversions through the *immediate priority ceiling protocol*.
>
> While it would be possible to achieve the same by allowing PPCs
> between PDs of the same priority, this would be much harder to
> statically analyse for loop-freedom (and thus deadlock-freedom). The
> drawback is that we waste a part of the priority space where a
> logical entity is split into multiple PDs, eg to separate out a
> particularly critical component to formally verify it, when the
> complete entity would be too complex for formal verification. For
> the kinds of systems targeted by the seL4 Core Platform, this
> reduction of the usable priority space is unlikely to cause problems.

The protected procedure implementation in the callee PD *must not
block*, i.e. it must execute on behalf of the caller at all times.
Ideally, this property should be enforced by the platform's build/analysis
tools.

**Note**

> Once the platform is extended to support concurrent (multicore)
> callee PDs, this will support concurrently serving one callee per
> core.

A PD providing a potentially long-running service, eg. a file system,
will require a protocol that returns to the caller without blocking,
with an indication that the operation is not complete, and use a
notification-based protocol to inform the callee when it is
time to retry the operation.

PPC arguments are passed by-value (i.e. copied) and are limited to 16 machine words.

**Rationale**

> This limitation on the size of by-value arguments is forced by the
> (architecture-dependent) limits on the payload size of the
> underlying seL4 operations, as well as by efficiency considerations.
> Similar limitations exist in the C ABIs (Application Binary Interfaces) of various platforms.

The seL4 Core Platform provides the callee with the (non-forgeable)
identify of the caller PD. The callee may use this to associate client
state with the caller (e.g. for long-running operations) and enforce
access control.

**Note**

> The caller identity is provided through seL4 *badged endpoint
> capabilities*, the seL4 Core Platform will provide each client with
> a different badged capability for the server's endpoint.

## Virtual machine {#vm}

A VM is a PD with extra attributes that leverage architectural support
for virtualisation. A VM will normally run a legacy OS binary and
applications. The whole virtual machine appears to other PDs as just a
single PD, i.e. its internal processes are not directly visible.

Virtual machines are to be fully described in later version of the
seL4 Core Platform definition. They are not intended to be made
available in the initial release of the platform.

## Trust

Trust is a multi-faceted concept that can have many areas of nuance.
A pure seL4 system allows for the construction of systems with complex trust relationships.
Such complex trust relationships make (formal or
informal) reasoning about security properties of the system
challenging and error-prone.

The seL4 Core Platform simplifies trust into a binary relationship
*between protection domains*:
A given protection domain may either trust or not trust another PD.
The trust relation is not symmetric: PD **A** trusts PD **B** does not imply that PD **B** trusts PD **A**.

Although much simplified compared to the generality of seL4, this
approach still supports a more nuanced model of trust than simply
labelling protection domains as *trusted* and *untrusted*: trust is
relative rather than absolute.

The default state of any trust relationship is *does not trust*.
For a given system a directed graph can be used to express the trust relationships of the protection domains.

For reasoning about a system's security properties it is important
that the trust relation is made explicit by the system designer. This
enables static analysis of trust, for example to ensure that no PD
performs a PPC on a PD it does not trust.


# Runtime API

This section provides an overview of what the runtime API may look like.
At this point it is meant to be informational only, and is not to be considered the defined API.
A full API shall be made available as part of future detailed design and implementation phases.

## Types

`Channel` is an opaque reference to a specific channel.
This type is used extensively through-out the functional API.

`MemRef` is an opaque reference to a memory location with an attached memory region.

## Entry Points

### `void init(void)`

Every protection domain must expose an `init` function.
This is called by the system when the protection domain is created.
The `init` function executes using the protection domain's scheduling context.

### `void notified(Channel channel)`

The `notified` entry point is called by the system when the protection domain has received a notification via a communication channel.
A channel identifier is passed to the function indicating which channel was notified.

### `void protected(Channel channel)`

The `protected` entry point is optional.
The `protected` entry point is called by the system when another PD
makes a protected procedure call to the PD via a channel.
The caller is identified via the `channel` parameter.

When the `protected` entry point returns, the protected procedure call
completes (i.e. control returns to the caller).

## Functions

### `void notify(Channel channel)`

Send a notification to a specific channel.

### `void ppcall(Channel channel)`

Perform a protected-procedure call to a specified channel.

### `MemRef memref_encode(Channel channel, void *p)`

Given a pointer to a location in virtual memory, create a memory reference referring to that pointer.

The memory reference is valid for the specified channel.

A NULL memory reference is returned on error.

### `void * memref_decode(Channel channel, MemRef memref)`

Given a memory reference for a specific channel decode the memory reference into a pointer.

A NULL pointer is returned on error.

### `MemRef memref_transcode(Channel from_channel, Channel to_channel, MemRef memref)`

Directly decode/encode a `memref` associated with `from_channel` to a memref associated with `to_channel`.


# Mapping to seL4 Constructs

This section gives an overview of how each of the seL4 Core Platform concepts maps to the underlying seL4 APIs.

This intention of this is to provide readers familiar with the underlying seL4 concepts a better understanding of the abstractions presented in this document.

## Channels

Each channel has an seL4 *badge* that uniquely identifies a caller PD to the
callee. In other words, for each client of a particular PD there must
be a different badge, although badges used by different callees are
independent (i.e. badges are not system-wide unique).

The badge identifies the channel's caller, irrespective of whether the
caller invokes the callee's `notification` or `protected` entry
point (if provided).

The badge thus serves for the caller as a unique client ID, and can
be used to tag per-client state.

The seL4 Core Platform does not support more than one channel between
any pair of PDs.

This means that the maximum number of client a PD can have is
determined by the dataword inside the seL4 badge (28 on 32-bit and 64
on 64-bit architectures).

## Notifications

The PD's SC is initially associated with its TCB for executing the
`init` entry point. When that returns, the Platform binds the SC to the PD's Notification.

Note: If a PD offers a `protected` entry point, then its Notification shall
be bound to the TCB. If the PD has no `protected` entry point, it
doesn't have an endpoint either, so the TCB must directly receive from
the Notification. I.e. implementation differs a bit between the two
cases, although that is hidden inside the Platform.**

## Protected procedure calls

The PPC mechanism abstracts over seL4 IPC. A PD providing a
`protected` entry point must have an seL4 endpoint to enable the
control transfer, as well as an seL4 *passive TCB* (i.e. with no
scheduling context attached).

To perform a PPC, the caller uses the *seL4_Call* system call, transferring
the caller's scheduling context to the callee.
The callee executes on the caller's scheduling context until the return of the
protected procedure.

The callee PD's passive TCB waits on the PD's endpoint using **seL4_Recv** or **seL4_ReplyRecv**.

<!--  LocalWords:  PDs Cspace
 -->
