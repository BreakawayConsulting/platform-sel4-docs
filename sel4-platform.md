% The seL4^\textregistered^\ Core Platform
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
* leverages seL4's strong isolation
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

## Why?

The Unix model is now [over half a century
old](https://link.springer.com/content/pdf/10.1007%2F3-540-09745-7_2.pdf). It
was great when it was created, it started getting a bit dated by the
time it became standardised as Posix in 1988, and it is really not
longer the right model. Hence, we specifically do *not* aim to be
Posix compatible, and instead try to come up with what is best for
seL4 and its use cases.

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

The seL4 Core Platform provides [virtual machines](#vm) so you can run
a Linux OS to support your legacy stacks.

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
* [notification](#notification)
* [protected procedure call (PPC)](#ppc)
* [virtual machine (VM)](#vm)

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

## Memory regions {#region}

A memory region is a contiguous range of physical memory.
A memory region must be at least page size.
The size of a memory region must be a power-of-2 multiple of the base
page size (4KiB) and the region must be aligned to its size.

A memory region may be mapped into a protection domain.
The mapping has a number of attributes, which include:

* the virtual address at which the region is mapped in the PD
* caching attributes (mostly relevant for device memory)
* permissions (full access, R/O, X/O).

**FIXME: The VA be better also aligned to the region's size.**

A memory region may be mapped into multiple PDs; the mapping addresses
for each PD may be different. A memory region can also be mapped
multiple times into the same PD (for example, with different caching
attributes), the address of such multiple mappings must be different. **FIXME: a clarification why VA of multiple mappings must be different would be helpful here. An example would also be good. A scenario I can think of is [Read-Copy-Update](https://en.wikipedia.org/wiki/Read-copy-update) but unsure if it applies here**

A memory region may also be *attached* to a communication channel (see
below), irrespective of whether the region is mapped into any PD or not. Such
an attachment supports transmission of data structures with memory
pointers.
**FIXME: I would assume this only works if the region is also mapped
to both PDs and it's mapped at the same address in those PDs. However,
I don't understand what it means for the region to be attached to a
channel in this case.**


## Communication Channels {#cc}

Protection domains can communicate (exchanging data, control or both)
via *communication channels*. Each channel connects exactly two PDs;
there are no multi-party channels. Each pair of PDs can have at most
one communication channel.

Communication through channels may be uni- or bi-directional in terms of data, but is always bi-directional in terms of information flow -- channels cannot
prevent information flowing both ways. **FIXME: a discrimination between "data" and "information" is needed here, or the statement is unclear. Perhaps  "information" means the "fixed length communication messages, including ACK messages". In such case this statement would imply that every piece of data is acknowledged by the recipient (or presumed lost), there is no datagram-type communication.**

Communication between two PDs does in general **not** imply a specific trust relationship between the two PDs.

A communication channel between two PDs provides the following:

* Ability for each PD to *notify* the other PD.
* Ability to *reference a memory region* associated with the communication channel.
* Ability for one PD (the client) to make *protected procedure calls* (PPCs) to the
other PD (the server).

A PPC channel is directed: it has a *caller PD* which can invoke a PPC to a *callee PD*. This form of channel *does* imply a trust relationship: the caller trusts the callee.

The overall communication relationships between protection domains can be expressed as a non-directed, cyclic graph.


### Protected Procedure Calls {#ppc}

A protected procedure call (PPC) enables the caller PD to invoke a
*protected procedure* residing in the callee PD. This is uni-directional, the roles of caller and callee cannot be reversed. The caller PD must trust the callee PD.

A PD can have at most one protected procedure. Arguments ("opcode") passed through the call can be used to choose from different functionalities the callee
may provide, according to a callee-defined protocol.

The seL4 Core Platform provides a *static architecture*, where all PDs
are determined at system build time. In such a system, the PPC call
graph can be statically determined, which supports determining certain
security and safety properties by static analysis.

The PPC in the system form a directed, acyclic graph, i.e. they
*cannot contain loops*.

**FIXME: THe following discussion seems redundant, as the pio
assignment rule already guarantees all relevant properties.**
I.e.: It is not valid that have PD *A* calling PD *B*, which in turns calls PD *A*.
It is an error to construct a system that contains loop (such an error should be determined at construction time in a static system; in a dynamic system managers must ensure changes to the system do not introduce loops).

It is allowed for a protected procedure to make a PPC as long as it does not cause a loop.
For example, PD *A* can call PD *B*, which in turn calls PD *C* as
part of protected procedure.
**END FIXME**

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
block*, ie it must execute on behalf of the caller at all times.
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

PPC arguments are passed by-value (i.e. copied) and are limited to 64 machine words. **FIXME:
This is too high, it could be 512B, which is more than seL4 supports
(I think) and certainly more than should ever be used. 64B seems more appropriate.**
Bulk data transfer must use a by-reference mechanism using shared
memory (see below).

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
> a different badged capability for the servers's endpoint.

**FIXME: Client/server pops up here for the first time, before we were
only talking about caller/callee. I think we should introduce this
terminology earlier.**

### Shared Memory

A communication channel may have an attached shared memory region.
The memory accessible read-write (but not executable) by both
protection domains sharing the channel.

**FIXME: I'm still not sure whether shared memory is necessarily
attached to a channel. Obviously, any shared memory constitutes a
channel, and if we want to have only one channel per PD pair, then
there can only be channel-associated mapped regions. [gernot]**

The region size can be an arbitrary number of pages, but must be
mapped into contiguous virtual memory. **FIXME Above we said it was a
power of two. The continuous virtual mapping is already implied above
by defining a memory region as contiguous in PM and mappable at a
particular VMA**
The virtual memory region need not be the same in each PD.
[Note: we may want to restrict to power-of-two to allow fast offset verification.]

In the case of PPC the server PD maintains a mapping from callee
identity (badge) to the virtual memory. **FIXME: Not sure what this
means. [Gernot]**

A PPC must *never* pass virtual-memory addresses directly, they must
be converted to offsets into the channel-attached memory region.
[Note: There are possibly neat implementation tricks to make this fast especially is the region is sufficiently aligned].

**Note**

> The seL4 Core Platform does not presently impose a structure
> on a channel-attached memory region. We expect that future versions of
> the specification will specify semantics for part of the shared region (headers).


### Notifications ### {#notification}

A notification is a semaphore-like synchronisation mechanism. A PD can
signal another PD's notification to indicate availability of data in
channel-associated memory. The notification transfers the signalling
PD's unforgeable identity. There is no payload associated with a
notification.

**Note**

> Details of the notification protocol are not presently defined
> by the seL4 Core Platform.

Depending on the assignment of priorities and cores to PDs, a PD's
notification may be signalled multiple times (bu different clients)
before the PD can start processing them. The receiving PD can identify
the different clients and process all requests. However, if a client
signals the same PD multiple times before that PD gets to process the
notification, it will only receive it once (it behaves as a binary
semaphore).

**Note**

> The number of unique notifiers per PD is limited to the number
> of bits in a machine word by the underlying seL4 Notification
> mechanism. **FIXME: I assume this is the same restriction (28 on 32bit and 64 on 64bit architecture) as described in Implementation.Channel section below. it would be good to clarify how such number came about, even if it requires some implementation details. **
> This is expected to be sufficient for the
> target application domains of the seL4 Core Platform. Should the
> number of notifiers exceed this limit, a more complex protocol will
> need to be specified that allows disambiguating a larger number of notifiers.**

## Virtual machine {#vm}

A VM is a PD with extra attributes that leverage architectural support
for virtualisation. A VM will normally run a legacy OS binary and
applications. The whole virtual machine appears to other PDs as just a
single PD, i.e. its internal processes are not directly visible.

**To be completed**

# Runtime API

## Types

`Channel` is an opaque reference to a specific channel.
This type is used extensively through-out the functional API.

`Memptr` is an opaque reference to a pointer. **FIXME: Do you really
mean reference to a pointer, or should this be an opaque reference to
a memory location? And I assume it is tied to a memory object?**
Memptr can be decoded into specific pointers.

## Entry Points

### `void init(void)`

Every protection domain must expose an `init` function.
This is called by the system when the protection domain is created.
The `init` function executes using the protection domain's scheduling context.
**FIXME: Presumably it will be called exactly once? How does it terminate?**

### `void notified(Channel channel)`

The `notified` entry point is called by the system when the protection domain has received a notification via a communication channel.
A channel identifier is passed to the function indicating which channel was notified.
**FIXME: More than one channel may have been notified. If so, I assume
the entry point will be called multiple times, based on some priority
convention (numerically largest bage)?**

### `void protected(Channel channel)`

The `protected` entry point is optional.
The `protected` entry point is called by the system when another PD
makes a protected procedure call to the PD via a channel.
The caller is identified via the `channel` parameter.

The parameters passed by the caller may be accessed via **FIXME**.
Any return values should be set via **FIXME**.

When the `protected` entry point returns, the protected procedure call
completes (i.e. control returns to the caller).


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

Decode the `memptr` to a DMA address.
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


## Static system

A static system is one where the protection domains that make up the
system are defined at system build time. Note that
a static system may be composed of dynamic protection
domains. **FIXME: unclear what this means. I assume you mean that a PD
may be created some time after sysinit, it can go away while the
system continues to run, and it can be re-created. Correct?**

## Dynamic system

A dynamic system has one (or potentially more) protection domains
which are capable of creating new protection domains at run-time, and
of managing the seL4 *Cspace* of other protection domains.

A dynamic system may be composed of both static and dynamic protection
domains. **FIXME: again, unclear.**



# Implementation

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
on 64-bit architectures). **FIXME: it would be good to clarify how such number came about, even if it requires some implementation details. ATM, this 'maximum number" does not follow from de description here above**

## Notifications

**The PD's SC is initially associated with its TCB for executing the
`init` entry point. When that returns, the Platoform binds the SC to the PD's Notification.**

**FIXME: If a PD offers a `protected` entry point, then its Notification must
obviously be bound to the TCB. If the PD has no `protected` entry point, it
doesn't have an endpoint either, so the TCB must directly receive from
the Notification. I.e. the coding differes a bit between the two
cases, although that is hidden inside the Platform.**

## Protected procedure calls

The PPC mechanism abstracts over seL4 IPC. A PD providing a
`protected` entry point must have an seL4 endpoint to enable the
control transfer, as well as an seL4 *passive TCB* (i.e. with no
scheduling context attached).

To perform a PPC, the caller uses the *seL4_CallWait* system call, transferring 
the caller's scheduling context to the callee.
The callee executes on the caller's scheduling context until the return of the
protected procedure.

The callee PD's passive TCB waits on the PD's endpoint using **seL4_Wait** or **seL4_ReplyWait**.

If the scheduling context does not provide sufficient *budget*, then [**FIXME: detail needed here, can be an error, can require server to context switch the TCB back to waiting on something else.**]

<!--  LocalWords:  PDs Cspace
 -->
