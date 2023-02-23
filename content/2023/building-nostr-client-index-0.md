+++
title = "Building a nostr client [0]"
date = 2023-02-19
draft = true
[taxonomies]
tags = [ "nostr", "rust" ]
+++

Over the past few weeks, [nostr](https://nostr.how/) has continued to take much of my attention. I'm still
fascinated by this protocol and I'm very curious to see where it goes in the coming years.

If you haven't heard of nostr yet, it stands for "Notes and Other Stuff Transmitted over Relays", and is a pretty
simple, yet powerful, idea for defining and growing a social network. Instead of a centralized server (or even
federated servers that talk to each other) it uses the concept of "relays" that allow clients to connect to them and,
you guessed it, _transmit_ "notes" and "other stuff", using a cryptographic key pair to sign and verify that data.

> <i>By the way, how do people pronouce this thing? Is it "nos-ter", "nose-ter", ... something else? I tend towards the
> first way for some reason.</i>

As the protocol's [GitHub](https://github.com/nostr-protocol/nostr) states:

> The simplest open protocol that is able to create a censorship-resistant global "social" network once and for all.
> It doesn't rely on any trusted central server, hence it is resilient; it is based on cryptographic keys and
> signatures, so it is tamperproof; it does not rely on P2P techniques, and therefore it works.

Clients have the option to connect to as many or as few relays as they want, some of which are free and open to the
public, and some of which require payment to access. This allows for a wide variety of communities to coalesce
around certain relays if they choose, and move to another if the one they are using decides to censor them for
any reason.

The implications of this are pretty amazing, and I think it will open up a lot of opportunity in so many directions.
Not only from the standpoint of free speech, but also for relay operators and client developers to build features in
a competitive way, very quickly raising the bar for the network as a whole. We are still very much in the early days,
and things are a little bit crazy, but the hype is real, and I believe for good reason.

### Let's build a client!

Besides all the reasons I mentioned above, I'm excited about nostr, because, as a programmer, I get to _build_ things.
My own things. Things that define how I interact with the network. There are a lot of good clients out there already,
but I figured, "why not try and build my own?"

This is the first entry (index `0`) in a series of posts I intend to write outlining the basic discovery and process
of building a client. Hopefully we'll run into some interesting challenges that need thoughtful solutions, and we'll
progress towards something relatively usable.

I'll be writing this series as I develop the client (seriously, I haven't written a single line of code as I
write this sentence), which is something I've never done before. I'll do my best to strike a balance between content
and pace. I don't want to dump every single thought in my head out into this post, otherwise it could take hours
to read, but I want to show enough to get an idea of what it takes to build a client at a technical level. I'll also
have to stop writing these posts at _some_ point (I'm getting married this year and there's more to life, ya know?)
but, I'll keep developing the client after I wrap up this series, and anyone can follow along on GitHub once we hit
that point.

> Hopefully I won't give so much detail that it's exhausting to read. I'm hoping I'll get better about tightening up
> these posts as I go.

### THE STACK

I'll be writing this client using Rust. That's it. That's the stack.

It'll be a terminal-based client, because frankly it's just easier, but I also love the challenge of making a usable
terminal UI. There's a neat minimalism there.

> I will definitely assume some Rust knowledge for this series. There are a million ways to learn Rust and I can't
> really teach it any better. I'll make clarifying notes if I think something is particularly odd about Rust that
> needs explaining, but I want to keep it to a minimum.

### The Protocol

Nostr, as a protocol, is refreshingly simple. The main GitHub [repository](https://github.com/nostr-protocol/nostr)
is a high-level look at the protocol and motivations behind it, but the NIPs
[repository](https://github.com/nostr-protocol/nips) is where all the action is.

[NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md) is one of the few mandatory NIPs that relays
and clients must implement, and is the obvious starting point for us. Highly recommend giving it a quick once over
before continuing.

#### Events

Looking at the first available struct defined in NIP-01, let's take a stab at defining it in Rust. I want to start
with the event generation and signing portion first, before we start connecting to relays.

```rust
pub enum Kind {
    SetMetadata,     // kind: 0
    Text,            // kind: 1
    RecommendServer, // kind: 2
}

pub enum TagId {
    PubKey, // tag: "p"
    Event,  // tag: "e"
    Other,  // ... not sure how to handle this yet
}

// simple 3-tuple that will be rendered as a JSON array
// e.g. ["e", "<hex>", "wss://some.relay.net"]
pub struct Tag(TagId, String, Option<String>);

// Event is our core data structure.
// It will likely not be built directly like this, but rather from a function,
// where the `id` will generated and the entire thing (possibly) signed.
pub struct Event {
    pub id: String,
    pub pubkey: String,
    pub created_at: u64,
    pub kind: Kind,
    pub tags: Vec<Tag>,
    pub content: String,
    pub sig: String,
}
```

As noted in the comments, we have some things to figure out as we get further, but for now this gives us a solid
place to stand. It may make more sense to use more specific types for some of these fields, but I want to start
simple for now.

Next, we need a way to generate the `id` for the event.

> To obtain the event.id, we sha256 the serialized event.
> The serialization is done over the UTF-8 JSON-serialized string
> (with no white space or line breaks) of the following structure:
>
> ...

I'll be honest, I'm a little confused by the "with no white space or line breaks" comment. Does that also mean
for the _content_? I could see it either way, but I'm going to lean towards we don't manipulate the content in any
way to obtain this event `id`.
