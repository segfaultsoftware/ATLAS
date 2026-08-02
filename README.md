# ATLAS

ATLAS (Astrogation, Transit & Logistics Access System) is a webapp which functions as both a SRD for a TTRPG by the same name and as an in-game tool. In the TTRPG, all players have access to a handheld interface with their ship. This interface is called ATLAS. In-game, ATLAS functions as the players number-crunching machine for communications, logistics, ship interfacing, and personal stats. Out of game, it acts as a character sheet, orchestration tool, map, and log.

## Table of Contents

### Development

- [Personas](docs/development/personas.md)
- [Requirements](docs/development/requirements.md)

### SRD

- [ATLAS SRD](docs/srd/atlas-srd.md)

## Manual

The database-backed Manual uses the landing-page slug configured by
`Rails.configuration.x.manual.landing_page_slug`. It defaults to `index` and
can be overridden with the `MANUAL_LANDING_PAGE_SLUG` environment variable.

To promote an existing Google-authenticated user to Webadmin, run:

```sh
bin/rails console
User.find_by!(email: "admin@example.com").update!(role: :webadmin)
```

Users are assigned the `User` role by default. Webadmins are the only users
authorized to manage Manual content.
