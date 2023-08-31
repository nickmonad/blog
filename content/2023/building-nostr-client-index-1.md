+++
title = "Building a nostr client [1]"
description = "Relays and a simple TUI"
date = 2023-08-31
[taxonomies]
tags = [ "nostr", "rust" ]
+++

Welcome to the second installation of the "Building a nostr client" series. The goal of this series is to walk through
building a simple nostr client in Rust. If you haven't seen the first post [here](@/2023/building-nostr-client-index-0.md),
I would recommend doing so, as we'll build on those concepts. Also, if you aren't familiar with nostr and why I'm doing this,
that would be a good place to start as well!

In the last post we discussed the basic data structures of the protocol; how to build them, and what basic Event signing
could look like.

In this post, I want to start connecting to relays, and build a simple TUI (terminal user interface) to display events.

### Building on prior art...

When I first considered doing this series of posts, I had the thought that I would do pretty much everything
"from scratch". Essentially, use libraries available to me in Rust, but nothing nostr specific. After finding the
[nostr crate](https://docs.rs/nostr/latest/nostr/index.html) and giving it some thought, I decided that I would, at the very least,
use its core data structures, event generation and signing capabilities to build my client. [yukibtc](https://github.com/yukibtc)
and other contributors have done an incredible job with this crate so far. Much better than I could do. It's easy
to understand and quite comprehensive.

So, in the interest of time, and future-proofing this project (I know I'd have to refactor my code to use the `nostr`
crate at some point anyway), I'll be using that crate moving forward. Even so, I want to explore some different methods
of relay interaction that depart from the sibling [nostr-sdk](https://docs.rs/nostr-sdk/latest/nostr_sdk/index.html)
crate, so we'll have plenty of code to write there.

Moving on!

### Relays

Relays are the backbone of the nostr protocol. They are responsible for accepting events and sending them on to
interested clients. By design, there are many relays a client could possibly connect to. Some require payment for access,
but many are free. Some are built for a specific community or topic in mind, but most right now seem to be pretty
free-form. If one relay goes down, for any reason, temporarily or permanently, clients can just connect to another.

Clients connect to relays and send events (or "notes") across them, and clients on the other end set up _filters_
for those events. Not every user is automatically connected to every other user, as they would be on the global
feed of a centralized platform, so there are some issues around discovery, as you need to know which relays
people are posting to. But, in practice, it's not a big deal. (And there are some NIPs out there attempting to mitigate this.)

As you start to think about how a client should interact with its configured relays, you tend to realize:

1. **There is no "should".** Other than the basic data over-the-wire requirements of the protocol, clients can and actively do
all sorts of things to transmit and receive events to and from relays. Without [The Algorithm](https://github.com/twitter/the-algorithm)
handed down from on high, there are really no rules here. You want events chronologically? Great. You want events from your
followed accounts and the accounts they follow? Sure. Only show events whose ID ends with the hex digit `f`? I guess.
Allow the user to selectively send events to some relays but not others? Yes, absolutely.

2. **It's suprisingly deep.** There are a lot of practical elements to consider when building a client's view
of the nostr world, especially in a "twitter-like" way. Generally you want to have the option of viewing something other than the "global" feed
of all their connected relays, as it can either be extremely spammy, or just too much information, too quickly. So,
you need some kind of view filtering, even if it's just showing events from the user's followed accounts. Also, what if the user
is away from the client for a while (say a month) and decides to come back? Do you start showing them events from exactly
where they left off? It might take them a while to scroll through and catch up to current events. Do you fetch older events
if they scroll in reverse chronological order? How many do you fetch at a time?

I could go on with plenty more rhetorical questions related to client/relay interaction. It really is the wild west
right now and there are a lot of opportunities to innovate in this space.

All that being said, I want to start as simple as possible. For now, we will support showing events from the user's
followed accounts, in the order we receive them. But first, we need to connect to some relays.

#### Finding a connection <3

Connecting to a relay is _relatively_ straightforward in principle, but somewhat difficult to manage in practice.

Fortunately, the really low-level details are already handled for us in a crate called
[tokio-tungstenite](https://docs.rs/tokio-tungstenite/latest/tokio_tungstenite/index.html). `tungstenite` is a popular
Rust crate for handling [WebSocket](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API) connections, which
nostr uses for its protocol communication layer. The "tokio" side of this crate just brings it into the
most popular ecosystem for asynchronous programming in Rust... [tokio](https://tokio.rs/).

> I believe the primary motivating factor for using WebSockets in nostr instead of some other transport protocol
> is that WebSockets are _everywhere_, especially modern web browsers. This means clients can work within
> or (in our case) outside a browser context. It also means clients can make one connection to a relay, and reuse that
> same connection for multiple things, reducing some of the connection overhead on the server.

> Another quick caveat: Like many aspects of this series, especially related to Rust, I certainly cannot do the asynchronous programming
> story justice here. It's another huge topic, deserving of near book-length treatments itself. Very simply put,
> asynchronous programming allows applications that primarily do I/O to scale quite far, with fewer resources.
> This is because I/O related tasks generally take waaaay longer than the tasks a CPU must perform, due to the high
> latency of the I/O device (disk, network, etc). Therefore, we can tell the asynchronous runtime we anticipate running
> some long I/O task, and that it can literally _wait_ for that task to complete, _while another task on the CPU runs_,
> typically on the same thread.

Essentially, we need to start a bunch of tasks that send and receive events from configured relays on their own time,
and have another task that is aggregating these events together in some way: de-duplicating them,
showing them to the user, saving them to disk, etc.

So, we need a way to spawn the async I/O task for each relay we want to interact with, and then communicate with that task
using nifty little tools called "channels". I'll try to illustrate how this is going to look.

#### Architecture

Relays are implemented as a Rust `struct` type, with a few properties. First, it must be configured with a WebSocket
URL, which is published by a relay operator, and is up to our client to store and use. Internally, a `Relay` must
also create and reference a "channel", that is used by the client to communicate with it asynchronously. These are
[`tokio::sync::mpsc`](https://docs.rs/tokio/latest/tokio/sync/mpsc/index.html) channels (**"multiple producer, single
consumer"**), and aren't exposed directly to the client, but is indirectly through a function interface, as illustrated
below. Relays are created in a `disconnected` state.

<div align="center"><img alt="nostr relay architecture disconnected" src="../images/nostr-relay-disconnected.png"/></div>

These "control" messages are used to tell the relay to send us events that match a certain filter
(as defined by [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md)), publish our own events, or disconnect.
They must be sent over a channel that the `Relay` manages since there is an underlying async task that must listen for
events from the relay and be responsive.

But first, we have to actually connect to the relay with its WebSocket address, and receive those events from it. When we
call the `Relay::connect()` method, we use the `tungstenite` crate underneath to open a WebSocket connection, and spin
up an async task to handle the "up" stream (messages _to_ the relay), and the "down" stream (messages _from_ the relay).
These "up" and "down" handles are also part of a `Stream` construct that is well beyond the scope of this post, but for
our purposes, "up" is like a `mpsc::Sender` and "down" is like a `mpsc::Receiver`.

<div align="center"><img alt="nostr relay architecture connected" src="../images/nostr-relay-connected.png"/></div>

These relay messages are written over the wire as `Message` types from the `tungstenite` crate, and are translated
from the `nostr::ClientMessage` and to `nostr::RelayMessage` types.

Lastly, we have to consider how it looks when there are multiple relays involved, as is expected within a nostr client.
When the `Relay::connect()` method is called, it expects to be given a `mpsc::Sender` side of a channel, which can
be cloned and given to _every_ relay we are interested in. These "producers" will all funnel to one "consumer" (`mpsc::Receiver`),
which acts as our firehose of events coming from all relays we have a connection with. There's nothing required about this,
it just makes it easier to deal with in a simple implementation like this one. We can treat all `Relay` structs as if they
were one big set of relays, producing a single stream of events.

<div align="center"><img alt="nostr relay architecture stream" src="../images/nostr-relay-stream.png"/></div>

As far as technical implementation details, there's a lot left to go over here. I think the best way to think about this
is you have an async task ("thread") driving the inbound/outbound connection with the WebSocket relay
itself, and another, at the client level, that is driving the state of the `Relay` struct, and that is why we need
to use async channels behind `Arc<Mutex<...>>` primitives, so they can be safely cloned and shared throughout the client as necessary.
The `Relay` struct is a effectively just a handle over a set of common data structures, making the initial connection and
shuffling data between this async task boundary.

With that, we have a _very_ simple nostr client interacting with relays! Here is some sample output that just shows
us connected to two major public relays, sending a filter for all kind `1` events after the current timestamp. When the
user hits Ctrl-C, we disconnect from each relay and shutdown.

```sh
$ RUST_LOG=info cargo run
   Compiling roostr v0.1.0 (/var/home/nickmonad/code/nostr/roostr)
    Finished dev [unoptimized + debuginfo] target(s) in 3.07s
     Running `target/debug/roostr`
[2023-08-26T19:59:28Z WARN  roostr] relay sent non-event message: EndOfStoredEvents(SubscriptionId("51102577c2f141aa2a06a10d3c2106b5"))
[2023-08-26T19:59:28Z WARN  roostr] relay sent non-event message: EndOfStoredEvents(SubscriptionId("5854bf7126a9337f9c35ea55dfdd5227"))
[2023-08-26T19:59:43Z INFO  roostr] EventId(0x078495389530eff3f78e86dcb14095f4c10d0bc80e9b1f5f0fa9bdab7c8a3c45)
[2023-08-26T19:59:45Z INFO  roostr] EventId(0x48627557bcac6d61d35946a74e5f3cf63a1057a0852b17f22d45bf530eaab8a3)
[2023-08-26T19:59:46Z INFO  roostr] EventId(0xe5954fe675db03fc5f0a1b4ea5d19f8de6fbd2cbf4be670fbd145652387d5136)
[2023-08-26T19:59:49Z INFO  roostr] EventId(0xfa9d99dc2e1a1e3c7c61dbb26d3929d1c0f82ec513d86403eb1790bcd6d1c25e)
[2023-08-26T19:59:50Z INFO  roostr] EventId(0xf2fe94cf82fb3d6dc39811320d43a9cbd0e1eaeb04ff7fb0a03ddea983a4ec21)
[2023-08-26T19:59:50Z INFO  roostr] EventId(0xf2fe94cf82fb3d6dc39811320d43a9cbd0e1eaeb04ff7fb0a03ddea983a4ec21)
[2023-08-26T19:59:50Z INFO  roostr] EventId(0xe4410e2d3714de65f21aa494ec89fb9e38ec69c05402143c5395cfe0df4e81fb)
[2023-08-26T19:59:53Z INFO  roostr] EventId(0x14b7f5f38998a93bb9dda045b72d55a3bab61bde4481b65c415e5503c61eb40c)
[2023-08-26T19:59:53Z INFO  roostr] EventId(0x953c7bb5884b57b98f54ddf227a8b437c3e061525e29a132c69f7848085df218)
[2023-08-26T19:59:55Z INFO  roostr] EventId(0x9f4a511bd1f6b02ccb4c4daea54a51b5daef6d78b126219fa234962efc5d8de7)
[2023-08-26T20:00:03Z INFO  roostr] EventId(0x84fec22e2056751d54c323fa4ff6ac3217d352f6f73eff84779fa3f7e5d48291)
[2023-08-26T20:00:07Z INFO  roostr] EventId(0xf7119e7250a7f6eaea5058254d850dcb7882428535f1aba1a3e511c5229aa00f)
^C[2023-08-26T20:00:11Z WARN  roostr] shutting down!
[2023-08-26T20:00:11Z WARN  roostr::relay] ["wss://relay.damus.io/"] user disconnect
[2023-08-26T20:00:11Z WARN  roostr::relay] ["wss://nostr-pub.wellorder.net/"] user disconnect
```

> The inital messages showing `EndOfStoredEvents` from each configured relay are due to the fact we set the `since`
> value on our filter message to be `Timestamp::now()` and the relay is just saying, "eveything after this will be in
> real-time."

### TUI

Now that we have events coming in from the relay, we can start on the real _client_ functionality. As I stated earlier,
this can go really deep on implementation, and wide on feature set. I want to keep things really simple, so
it won't do much for now.

To help set some direction on where to focus next, I think we can break it down like so:

* First, read a list of public keys to "follow" from a local config file.
* Using the public keys present in that config, setup and send filters to each relay, asking first for kind `0` events
associated with the public key(s), giving us "profile" metadata, like the user's preferred display name, followed by kind `1` events, the actual text notes,
from the past **day**. (Arbitrary choice.)
* Listening on the aggregated event stream, use some kind of mechanism to ensure that events aren't shown twice, in the case where
a followed public key is published to more than one of the relays we are interested in. This is quite common, and must be handled
by pretty much every client. There are really straightforward ways of handling this, using a list or map, but those come with tradeoffs
in performance and memory usage over time. We could use a SQLite based implemention, which I think would be ideal for a client like this,
but for now, let's just use a simple in-memory set, and vector (list) of events.
* Build a simple TUI (terminal user interface) for showing the events and navigating through the list.

This is the simplest possible start I can imagine, while building something at least marginally useful. Many factors of a "real" client
won't be considered here, but, it'll be fun to continue adding features over time.

#### Starting up

First, we need to read our config file, and create our primary `mpsc` channels. One for that relay "firehose" mentioned
above, and another for terminal events (user input, resize notifications, etc). The first block here is our example
`config.toml` file.

```toml
follow = [
    "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6", # fiatjaf
    "npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m", # jack
    "npub1qny3tkh0acurzla8x3zy4nhrjz5zd8l9sy9jys09umwng00manysew95gx", # odell
]

[[relay]]
url = "wss://relay.damus.io"

[[relay]]
url = "wss://nostr-pub.wellorder.net"
```

> In the long term, the config for `roostr` would be more related to behavior, and not have hardcoded npubs
> or relay URLs. These would be requested the first time a user started the client, and stored in a local database.
> Pubkeys to follow would ideally come from nostr `kind:3` events, published via our user's pubkey, but I decided
> not to implement that right now, since we don't have a database yet.

```rust
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // send logs to stderr
    env_logger::builder().target(Target::Stderr).init();
    // load config
    let config = Config::load("config.toml").await?;

    // event/relay message bus
    let (tx, mut rx) = mpsc::channel::<RelayMessage>(1024);
    // events from terminal
    let (events, mut input) = mpsc::channel::<TermEvent>(10);
```

Now, we can initialize our `Relay` structs, one for each URL we have listed in our configuration.

```rust
    // filter for all kind:0 metadata objects
    let metadata = Filter::new()
        .kind(Kind::Metadata)
        .authors(config.follows.clone());

    // filter for all kind:1 notes
    let notes = Filter::new()
        .kind(Kind::TextNote)
        .authors(config.follows.clone())
        .since(Timestamp::now().sub(ONE_DAY)); // statically defined `Duration` value

    // instantiate configured relays
    let mut relays: Vec<Relay> = vec![];
    for relay in config.relays {
        let r = Relay::new(relay.url.clone());
        r.connect(tx.clone()).await?;

        r.send(ClientMessage::new_req(
            SubscriptionId::generate(),
            vec![metadata.clone(), notes.clone()],
        ))
        .await?;

        relays.push(r);
    }
```

#### Processing and displaying events

Once the client has completed this initial startup, it can run its primary processing loop, reading events
from the relays, and user input from the terminal.

Since we aren't using SQLite right now as we prove all this out, we'll use an in-memory "database" structure.

```rust
// Simple "database" implementation,
// storing a list of Events, and a map of Metadata objects, accessible via pubkey
#[derive(Default)]
pub struct Database {
    pub events: Vec<Event>,
    pub metadata: HashMap<String, Metadata>,
}
```

The `metadata` attribute is important, as we want to show every pubkey's "username" as they have published them
under the `kind:0` event. Since we have a filter setup for those, we can update this struct as a mapping between the
followed pubkeys and their metadata. The `events` attribute is a simple vector of all the `kind:1` events we receive.

> Obviously, this isn't really scalable for "real-world" usage. We'd ideally push these to a local SQLite file,
> and maybe use these in-memory structures for a bounded cache. Just indefinitely growing this vector isn't
> efficient at all, but again, this is more of a proof-of-concept.

Finally, we can run our primary loop. Essentially, the client blocks while it waits for one of two types of
events: user input or relay events. For user events, the TUI will be given those events (other than the quit event),
and it will update its own state, like which nostr note is selected based on user selection.
For relay events, the database is updated. Incoming nostr events are de-duplicated, and then stored in the event list.

```rust
// setup our "database" and set of "seen" events, for de-duplication
let mut database = Database::default();
let mut seen: HashSet<EventId> = HashSet::new();

// setup tui
let mut tui = Tui::new()?;
tui.events(events);
// initial draw
tui.draw(&database);

// main event loop
// as messages/events come in, de-duplicate them
// and store them for display on the UI
loop {
    tokio::select! {
        // get events from the terminal
        event = input.recv() => {
            match event {
                Some(event) => {
                    if let TermEvent::Key(KeyEvent{ code, .. }) = event {
                        if code == KeyCode::Char('q') {
                            // user quit - disconnect from relays
                            log::warn!("[client] user quit!");
                            disconnect(relays).await.unwrap();
                            break;
                        }
                    }

                    // pass event to TUI struct, so it can update its own state
                    tui.update(event, &database);
                },
                _ => {}
            }
        }

        // get events from relay(s)
        msg = rx.recv() => {
            match msg {
                Some(msg) => {
                    match msg {
                        RelayMessage::Event { event, .. } => {
                            match event.kind {
                                Kind::Metadata => {
                                    // update metadata map, from pubkey to metadata
                                    let metadata = Metadata::from_json(&event.content).unwrap();
                                    database.metadata.insert(event.pubkey.to_string(), metadata);
                                },
                                Kind::TextNote => {
                                    // process note, ignore if we have seen already
                                    if !seen.contains(&event.id) {
                                        database.events.push(event.as_ref().clone());
                                        seen.insert(event.id);
                                    }
                                }
                                _ => {}
                            }
                        },
                        _ => log::warn!("relay sent non-event message: {:?}", msg)
                    }
                }
                None => {
                    log::warn!("all relay senders dropped");
                    break;
                }
            }
        }
    }

    // event(s) processed, draw another "frame"
    tui.draw(&database);
}
```

In both cases, after the event is processed, the TUI is re-drawn. In principle, there is some contention here. If there
is a delay in processing a relay event, user events will have to wait as they queue from the terminal input thread,
potentially causing a lag in the responsiveness. But, in practice, espcially in this case, the relay event processing
is so minimal, that it doesn't have an impact. If there were heavier processing involved, the client would likely have
to split off that processing onto another async task or thread and signal its completion back to this thread.

As for the actual processing requirements and performance of re-drawing the TUI, we don't have to worry about that
in practice either, since it's just... outputing text to the terminal.

Since this post is already way too long, I'll pass on explaining the actual TUI rendering in detail. Suffice it to
say, I chose to use [ratatui](https://docs.rs/ratatui/latest/ratatui/index.html), the successor to `tui-rs`. It
provides really simple ways to put the terminal in the correct mode it needs to be in, and build up layout components.

### Demo!

<script async id="asciicast-WvpaikA286wzkJ5RqBIIT6VzT" src="https://asciinema.org/a/WvpaikA286wzkJ5RqBIIT6VzT.js"></script>

Look at that TUI **magic!**

### Next Up

If you've stuck around this far, thanks for hanging in there. It took me way longer to publish this post than I wanted
it to take. It's been a really busy summer - full of good and beautiful things, just not as much coding time outside of work.

There's a lot that can still be done to make this TUI more functional, useful, and pretty. I think the first
thing I would do is make the rendered height of each note fixed and consistent, and allow the user to expand longer notes
if they want to read them. Since the terminal doesn't have a "continuous" scrolling frame, like a fully graphical UI would
have, notes of different length can really break the rendering flow while scrolling through, as you can see in the demo.

But, for now, let's move onto other things!

In the next (and likely final) installation of this series, I'll add some basic key management, paving the way
for signing and publishing events.
