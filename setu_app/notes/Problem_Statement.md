# SETU – Problem Statement

## Problem

During natural disasters, mass gatherings, or connectivity shutdowns, mobile networks and internet services often become unavailable, damaged, or heavily congested. As a result, people are unable to contact emergency services, share their location, or request immediate help.

Existing emergency applications — including India's 112 emergency number — depend on active cellular or internet connectivity, making them unreliable in exactly the moments they matter most.

---

## Challenges

- Disasters (floods, cyclones, earthquakes) damage towers directly
- Mass events (stampedes, festivals) overload standing towers with traffic
- Rural, hill, and border districts have patchy or no coverage on an ordinary day — a baseline gap, not just a disaster-time one
- Planned internet shutdowns remove the digital emergency channel entirely for hours or days
- Existing emergency apps become unusable exactly when they're needed most

---

## Our Solution

SETU is an offline-first emergency relay that turns any cluster of nearby smartphones into a Bluetooth / Wi-Fi Direct mesh network.

Instead of relying on mobile towers, every smartphone with the app installed becomes a relay node that forwards a signed emergency message until it reaches a device with internet, or reaches a mesh boundary. Once connectivity is available, the message reaches a backend, then a responder dashboard.

**This is deliberately scoped narrow.** The mesh core is demonstrated through two verticals — disaster SOS and women's-safety stealth mode — not fifteen domains at once.

---

## Objectives

- Enable emergency communication without internet or cellular signal
- Reduce the time between distress and a verified responder becoming aware
- Feed verified, prioritized reports into existing systems (112 / SACHET), not replace them
- Keep the security and adoption claims honest about what's demonstrated vs. roadmap

---

## Target Users

- Citizens in disaster-affected or low-coverage areas
- Institutional early adopters: event volunteers, NDRF/police devices, campus security (real coverage strategy — not dependent on random mass adoption)
- Verified responders: police, NDRF, disaster management authorities

---

## What SETU Is Not

- Not a replacement for 112 India or NDMA's SACHET — it's a feeder into them
- Not a district-wide or state-wide coverage claim — realistic range is cluster-level (a building, a stampede, a village), not wide-area
- Not a novel routing protocol — it builds on established delay-tolerant/epidemic-routing research; the genuinely new part is the urgency-prioritization and duplicate-collapsing logic on top of it

---

## Tagline

> **"Jab Network Toote, Setu Jode."** — The bridge that stays up when the network goes down.
