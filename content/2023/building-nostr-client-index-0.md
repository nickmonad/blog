+++
title = "Building a nostr client [0]"
description = "Basic data structures and Event generation"
date = 2023-03-26
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
have to stop writing these posts at _some_ point (there's more to life, ya know?). But, I'll keep developing the
client after I wrap up this series, and anyone can follow along on GitHub once we hit that point.

> Hopefully I won't give so much detail that it's exhausting to read. I'm hoping I'll get better about tightening up
> these posts as I go.

Wait, what about the name? After looking at all sorts of weird combinations of "rust" and "nostr", I came up
with `roostr`. I like it because it gives the project its own identity, and is actually pronoucable as "rooster".

> I'm aware of the whole ostrich thing nostr has going for it. I just wanted some combination of "rust" and "nostr"
> and settled on something unique in the space!

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
    PubKey,  // tag: "p"
    Event,   // tag: "e"
    Unknown, // ... not sure how to handle this yet
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
place to stand. It may make more sense to use more specific types for some of these fields, and we will certainly
need to expand upon these, but I want to start simple for now.

Next, we need a way to generate the `id` for the event.

> To obtain the event.id, we sha256 the serialized event.
> The serialization is done over the UTF-8 JSON-serialized string
> (with no white space or line breaks) of the following structure:
>
> ```
> [
>   0,
>   <pubkey, as a (lowercase) hex string>,
>   <created_at, as a number>,
>   <kind, as a number>,
>   <tags, as an array of arrays of non-null strings>,
>   <content, as a string>
> ]
> ```

I'll be honest, I'm a little confused by the "with no white space or line breaks" comment. Does that also mean
for the _content_? I could see it either way, but I'm going to lean towards we don't manipulate the content in any
way to obtain this event `id`.

Before we can actually sign the event, we need that `id`, which means we need a method to generate the JSON string
described above, based on the event.

In the Rust world, [`serde`](https://serde.rs/) has become a go-to crate for (ser)ialization, and
(de)serialization, and has support for JSON, so it makes sense for us to start there. `serde` supports the notion
of a `Serialize` trait (or "interface"), we can implement to tell `serde` how we want our custom types to look when
they are represented as JSON. Explaining all the details of `serde` is definitely outside of the scope of this
post, but this should give you a rough idea.

For `Kind`, it's pretty straightforward, just map each `enum` variant to a number.

```rust
impl Serialize for Kind {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_u32(match self {
            Kind::SetMetadata => 0,
            Kind::Text => 1,
            Kind::RecommendServer => 2,
        })
    }
}
```

The `Tag` type is a little more complicated, since the 3rd element of the array is optional, according to NIP-01.

```rust
impl Serialize for Tag {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        // serialize tag
        let mut tup = if let Some(_) = &self.2 {
            serializer.serialize_tuple(3)?
        } else {
            serializer.serialize_tuple(2)?
        };

        // serialize tag "id"
        tup.serialize_element(match self.0 {
            TagId::PubKey => "p",
            TagId::Event => "e",
            TagId::Unknown => "unknown",
        })?;

        // serialize tag "payload"
        tup.serialize_element(&self.1)?;

        // serialize recommended relay (if we have it)
        if let Some(relay) = &self.2 {
            tup.serialize_element(&relay)?;
        }

        tup.end()
    }
}
```

I'm sure they are cleaner ways of handling both of these cases, but in the spirit of just getting things working,
let's stick with it.

Lastly, we need to consider the `Event` - the center of all this. I started to go down the route
of implementing `Serialize` for `Event`, so it would produce the `[0,...]` format described above, which we use
in determining the event `id`, but quickly realized that wouldn't be so great.

One thing that's really cool about Rust, or even just modern statically typed languages in general, is that we can
encode certain aspects of our problem domain into the types themselves. In this case, `EventData` is something dynamic,
generated by the user, and can reasonably be "edited", up until the point we are ready to sign the event for
publication to the network. Once that event is signed though, it doesn't make sense that we should be able to edit
that `EventData` anymore, since changing it necessarily changes the `id`, which changes the signature
(more on that later).

So, what if our `Event` type represented this idea directly?

```rust
#[derive(serde::Serialize)]
pub struct Event {
    pub id: String,
    pub sig: String,

    #[serde(flatten)]
    pub data: EventData, // this is the old "Event" type, without the id and sig
}
```

> The astute reader might comment that since our `Event` fields are "pub" here, it doesn't actually quite
> get us to the point where we have full encapsulation within this module. That's something I hope to address
> fully, with accessor methods later on.

With this design in mind, it wouldn't make sense to write `Serialize` for `EventData` in such a way that doesn't result in
the standard JSON representation of the struct, which we want to send over the wire to the relays. We want to lean
on `serde`'s provided implemention of `Serialize` for structs, and include the fields of `EventData` into our final
`Event` JSON representation, at the same level as `id` and `sig` (hence the `flatten` directive). So, we can't
use `Serialize` to build our array for determining the event `id`. We'll have to write a simple function to do that
using string formatting.

OK! That was a bit of a detour, but hopefully a fruitful one. Here's what we have now for `EventData` and `Event`.

```rust
#[derive(serde::Serialize)]
pub struct EventData {
    pub pubkey: String,
    pub created_at: u64,
    pub kind: Kind,
    pub tags: Vec<Tag>,
    pub content: String,
}

impl EventData {
    pub fn id(&self) -> String {
        hex::encode(
            Sha256::new()
                .chain_update(format!(
                    // just lean on serde here as well, for each element.
                    // makes the format string nicer to look at
                    "[0,{},{},{},{},{}]",
                    json::to_string(&self.pubkey).unwrap(),
                    json::to_string(&self.created_at).unwrap(),
                    json::to_string(&self.kind).unwrap(),
                    json::to_string(&self.tags).unwrap(),
                    json::to_string(&self.content).unwrap(),
                ))
                .finalize(),
        )
    }
}

// Event can only be generated from EventData,
// with a provided key for signing.
#[derive(serde::Serialize)]
pub struct Event {
    pub id: String,
    pub sig: String,

    #[serde(flatten)]
    pub data: EventData,
}
```

Now, we can create a simple test case for `EventData`, and make sure we are getting some `id` back from it.

```rust
#[test]
fn event_id() {
    // sample event
    // https://www.nostr.guru/e/c8d24e78cfedd658688bdfc23a2f7049f0032989096f3e1c5df1e5585efaa393
    let data = EventData {
        pubkey: "5fe74dc9a7349be18269007d8e7bdf7599869cb677fe3f2794ebd821f146fe81".into(),
        created_at: 1675631070,
        kind: Kind::Text,
        tags: vec![],
        content: "hello, nostr".into(),
    };

    assert_eq!(
        data.id(),
        "c8d24e78cfedd658688bdfc23a2f7049f0032989096f3e1c5df1e5585efaa393"
    );
}
```

#### Signatures

The next critical piece we need to consider is signing the events with a key pair.

By utilizing digital signatures, nostr clients and relays can verify the integrity of messages. They are the core piece
of a user's identity as they move from one relay to another. This what people mean when they say nostr is
"tamperproof". As long as you practice secure handling of your keys, no one can generate fake events associated with
your public key.

As stated in the NIP-01 specification,

> Each user has a keypair. Signatures, public key, and encodings are done according to the Schnorr signatures
> standard for the curve secp256k1.

The whole cryptography thing is a _h u g e_ topic to cover, and I am by no means an expert, so I won't go into much
detail. The basic idea is that everybody has a public key and a private key. This is called the "key pair".
A user can "sign" data with their private key, and share their public key with the world. Anybody can then look
at the signature data, and verify it was in fact signed by the user with the associated public key, all without
revealing the private key itself, so it can be re-used.

Fortunately, there is a lot of prior art out there we can utilize to get this working pretty easily.

I'll be using the [`secp256k1`](https://docs.rs/secp256k1/latest/secp256k1/index.html) crate, which has support
for Schnorr signatures as well. We'll also need the [`bech32`](https://docs.rs/bech32/0.9.1/bech32/) crate to
support encoding and decoding of keys in a user-friendly way.

First, let's build the signing context and key pair, by reading a value from the environment. Nostr keys use the `bech32`
encoding, so private keys begin with `nsec1` and public keys begin with `npub1`. This makes it easier for a human
looking at values to know which they are dealing with. The public key can be derived from the private key, so we
only need to include the latter in our configuration.

```rust
#[derive(Parser, Debug)]
pub struct Config {
    #[clap(env = "ROOSTR_PRIVATE_KEY")]
    pub key: SecretString,
}

...

pub struct Signer {
    context: Secp256k1<All>,
    keypair: KeyPair,
}

impl Signer {
    pub fn from_config(config: &Config) -> anyhow::Result<Self> {
        // decode `nsec1...` into Vec<u5>
        let (_, decoded, _) = bech32::decode(&config.key.expose_secret())?;

        // create Vec<u8> from Vec<u5> ("base32")
        let bytes: Vec<u8> = Vec::from_base32(&decoded)?;

        // generate a secret key on the curve from the byte vector
        let context = Secp256k1::new();
        let key = SecretKey::from_slice(&bytes)?;
        let keypair = KeyPair::from_secret_key(&context, &key);

        Ok(Self { context, keypair })
    }

    ...
}
```

> From a security standpoint, this isn't ready for production. I'm currently doing just about the bare minimum here
> in order to get this working, by using this `SecretString` type imported from the [`secrecy`](https://docs.rs/secrecy/0.8.0/secrecy/)
> crate, which basically just zeros out the memory allocation when the value's memory is freed, and makes it very explicit
> when we expose the secret value to other functions. We'll revisit this topic of key management in a later post.

Now that we have that, we can write the function that will sign our event `id`.

```rust
impl Signer {
    ...

    // public key returned in the "x only" format,
    // which drops the first parity byte
    pub fn public_key(&self) -> String {
        format!("{:x}", self.keypair.x_only_public_key().0)
    }

    pub fn sign(&self, id: &str) -> anyhow::Result<String> {
        let message = Message::from_slice(&hex::decode(id)?)?;
        let signature = self.context.sign_schnorr(&message, &self.keypair);

        Ok(format!("{signature:x}"))
    }
}
```

I had to find the [`KeyPair::x_only_public_key`](https://docs.rs/secp256k1/latest/secp256k1/struct.KeyPair.html#method.x_only_public_key)
function after I had originally just tried to test with [`KeyPair::public_key`](https://docs.rs/secp256k1/latest/secp256k1/struct.KeyPair.html#method.public_key)
which seems to include some kind of "parity" byte at the front of the hex output. I can't see that being relevant
when looking at the raw data of other valid nostr events out in the wild, so I don't think it's necessary. This makes
sense actually when we see that "X only" intends the key to be used only for signature verification.

Finally, we can put our types together in the way we described above to generate a signed `Event` from `EventData`.

```rust
#[derive(serde::Serialize)]
pub struct EventData {
    pub created_at: u64,
    pub kind: Kind,
    pub tags: Vec<Tag>,
    pub content: String,
}

impl EventData {
    pub fn id(&self, pubkey: &str) -> String {
        hex::encode(
            Sha256::new()
                .chain_update(format!(
                    // just lean on serde here as well, for each element.
                    // makes the format string nicer to look at
                    "[0,{},{},{},{},{}]",
                    json::to_string(&pubkey).unwrap(),
                    json::to_string(&self.created_at).unwrap(),
                    json::to_string(&self.kind).unwrap(),
                    json::to_string(&self.tags).unwrap(),
                    json::to_string(&self.content).unwrap(),
                ))
                .finalize(),
        )
    }

    pub fn sign(self, signer: &Signer) -> anyhow::Result<Event> {
        let pubkey = signer.public_key();
        let id = self.id(&pubkey);
        let sig = signer.sign(&id)?;

        Ok(Event {
            id,
            sig,
            pubkey,
            data: self,
        })
    }
}
```

You may notice, I also changed up the the type definitions a little bit here. I found it a bit awkward to have the
`pubkey` of the signing key pair on the `EventData` struct. So instead, I added it as a parameter to the `id()`
generation function, which is then utilized in the `sign()` function. This all seemed a bit cleaner to me,
as I really only have to give the signing "context" _once_ when `EventData` is actually signed and produces
an `Event`.

It's also worthwhile to note some Rust semantics here. In the `sign()` function signature (no pun intended), there's
this `self` parameter, which doesn't include the more common `&`, or immutable reference. In this case, we
actually want the `sign()` function to take "ownership" of the `EventData`, consuming it in a such a way that prevents
the caller from using _their_ reference to it anymore, which helps us to encode this idea that once you sign `EventData`,
it really shouldn't be modified anymore.

#### The Result

Finally, we can generate a fully valid nostr `Event`!

```rust
use clap::Parser;
use roostr::event::{Kind, EventData};
use roostr::signature::Signer;
use roostr::Config;

fn main() -> anyhow::Result<()> {
    dotenv::dotenv().ok();

    let config = Config::parse();
    let signer = Signer::from_config(&config)?;
    let data = EventData {
        created_at: 1678648700,
        kind: Kind::Text,
        tags: vec![],
        content: "hello, reader!".into(),
    };

    let event = data.sign(&signer)?;
    println!("{:#?}", event);

    Ok(())
}
```

Let's `cargo run` that.

```rust
Event {
    id: "bba6b589e2cc685eb26b5558184ed3022bc5181364d16b83be73410d37fed84e",
    sig: "c91c91e86b6359e5ba364cd40450886ed3f34e0b7a0f5765c23f8426390ff5e23ac2c7846a351bca62b18482414a2dea7d09051b20745ff9107f11e8320a8ea7",
    pubkey: "e241ea8967a43f8c67eff8b16311a204fcc50906e5c2c5c87d1ec7422ea1a6d5",
    data: EventData {
        created_at: 1679855436,
        kind: Text,
        tags: [],
        content: "hello, reader!",
    },
}
```

### Next Up

I do plan on releasing this on GitHub in the near future. Once I have simple relay interaction working, I think it'll
make sense to do so. Part of this exercise is for my own learning experience as well, so I'm not quite ready to accept
pull requests just yet.

In the next post in this series, we'll look at connecting to relays, and building a simple user interface to read
messages from those relays.
