Title: Introduce claims intake and adjudication contracts

Summary

- Adds two independent Clarity contracts with no cross-contract calls or traits.
- intake-and-triage: Policy registry, FNOL intake, deterministic severity scoring.
- adjudication: Adjuster registry/assignment, damage + fraud scoring, settlement lifecycle.

What changed

- New: contracts/intake-and-triage.clar
- New: contracts/adjudication.clar
- Updated: Clarinet.toml to register both contracts

How to test

- clarinet check
- clarinet console to invoke public functions

Notes

- Example/demo only; on-chain scoring is simplistic and deterministic.
- Warnings from clarinet about unchecked data are acceptable here (typed inputs only).