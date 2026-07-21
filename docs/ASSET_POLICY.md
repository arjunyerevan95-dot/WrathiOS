# Commercial asset policy

## Absolute rule

WRATH's commercial game data must never be committed to this repository, attached to issues, uploaded as CI artifacts, or included in public IPA files.

Owning the game grants the owner the ability to use their copy. It does not grant this project permission to redistribute the data to everyone else, a distinction software projects periodically rediscover after receiving unpleasant letters.

## Prohibited content

This includes, without limitation:

- the `kp1` game-data directory
- maps and compiled level data
- textures, models, sprites, shaders, fonts, and interface artwork
- music, dialogue, sound effects, and cinematics
- commercial archives or extracted archive contents
- proprietary configuration or platform SDK material copied from a retail installation

## Permitted content

The repository may contain:

- GPL-compatible upstream engine source
- project-authored iOS platform code
- build scripts and manifests
- documentation
- original placeholder graphics and sounds created for the port
- hashes, filenames, sizes, and structural metadata needed to validate user-owned data, where legally appropriate

## Runtime import design

The application will eventually ask the user to select files from a licensed WRATH installation through the iOS document picker. The importer will validate compatibility, copy or coordinate access within the sandbox, and report errors without uploading the files anywhere.

## Development evidence

Logs and screenshots must be reviewed before publication. They must not expose private filesystem paths, account identifiers, authentication tokens, or proprietary data contents beyond what is visually present during ordinary gameplay.
