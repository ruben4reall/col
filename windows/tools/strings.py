"""Writes Col for Windows' string tables (src/Col/Resources/Strings.resx and Strings.fr.resx) from the list below.

Edit the words here, then run: python3 windows/tools/strings.py
"""
from pathlib import Path
from xml.sax.saxutils import escape

NB = " "  # French puts a no-break space before : ? ! and inside guillemets.

STRINGS = {
    # The island.
    "Island_Home": ("Home", "Accueil"),
    "Island_Live": ("Live", "En direct"),
    "Island_Tools": ("Tools", "Outils"),
    "Island_Settings": ("Settings", "Réglages"),
    "Home_NothingPlaying": ("Nothing is playing", "Rien ne joue"),
    "Home_NothingPlaying_Detail": (
        "Play a song in Spotify, your browser or any player, and it shows here.",
        "Lancez un morceau dans Spotify, votre navigateur ou un autre lecteur, et il s'affiche ici.",
    ),
    "Lyrics_Off": (
        "Lyrics are off. Turn them on in Settings, Music and lyrics.",
        "Les paroles sont désactivées. Activez-les dans Réglages, Musique et paroles.",
    ),
    "Lyrics_Looking": ("Looking for the words…", "Recherche des paroles…"),
    "Lyrics_Instrumental": ("Instrumental", "Instrumental"),
    "Lyrics_Unavailable": ("LRCLIB cannot be reached right now.", "LRCLIB ne répond pas pour le moment."),
    "Lyrics_NotFound": ("No lyrics for this song.", "Pas de paroles pour ce morceau."),
    "Live_Empty": ("Nothing running", "Rien en cours"),
    "Live_Empty_Detail": (
        "Claude Code, Codex and your scripts show here while they work.",
        "Claude Code, Codex et vos scripts s'affichent ici pendant qu'ils travaillent.",
    ),
    "Agent_Waiting": ("Waiting for you", "Vous attend"),
    "Agent_Working": ("Working", "Au travail"),
    "Agent_Done": ("Done", "Terminé"),
    "Agent_Idle": ("Idle", "Au repos"),
    "Card_Heading": ("{0} · {1}", "{0} · {1}"),
    "Card_AnAgent": ("An agent", "Un agent"),
    "Card_Tool": ("Tool", "Outil"),
    "Card_More": ("+{0} waiting", "+{0} en attente"),
    "Card_Allow": ("Allow", "Autoriser"),
    "Card_Deny": ("Deny", "Refuser"),
    "Card_TooLong": (
        "Too long to check here: answer in the terminal.",
        f"Trop long pour être vérifié ici{NB}: répondez dans le terminal.",
    ),
    "Tools_Timer": ("Timer", "Minuteur"),
    "Tools_Start": ("Start", "Démarrer"),
    "Tools_Pause": ("Pause", "Pause"),
    "Tools_Cancel": ("Cancel", "Annuler"),
    "Tools_Minutes": ("{0} minutes", "{0} minutes"),
    "Tools_KeepAwake": ("Keep awake", "Rester éveillé"),
    "Tools_Clipboard": ("Clipboard", "Presse-papiers"),
    "Tools_Clear": ("Clear", "Effacer"),
    "Tools_Clipboard_Empty": (
        "Copied text shows here, kept in memory only.",
        "Le texte copié s'affiche ici, gardé en mémoire seulement.",
    ),
    "Tools_Clipboard_Off": ("Clipboard history is off.", "L'historique du presse-papiers est désactivé."),
    "Tools_Pin": ("Pin", "Épingler"),
    "Tools_Unpin": ("Unpin", "Désépingler"),
    "Tools_CopyAgain": ("Copy again", "Copier à nouveau"),
    "Timer_Done": ("Done", "Fini"),
    "State_On": ("On", "Activé"),
    "State_Off": ("Off", "Désactivé"),
    "Menu_Open": ("Open the island", "Ouvrir l'île"),
    "Menu_Settings": ("Settings…", "Réglages…"),
    "Menu_Quit": ("Quit Col", "Quitter Col"),
    # The settings.
    "Settings_Title": ("Col Settings", "Réglages de Col"),
    "Settings_Preview": ("Preview", "Aperçu"),
    "Nav_General": ("General", "Général"),
    "Nav_Music": ("Music and lyrics", "Musique et paroles"),
    "Nav_Agents": ("Agents", "Agents"),
    "Nav_About": ("About", "À propos"),
    "General_Launch": ("Open Col when you sign in", "Ouvrir Col à la connexion"),
    "General_Launch_Detail": (
        "Col starts with Windows and waits at the top of the screen.",
        "Col démarre avec Windows et attend en haut de l'écran.",
    ),
    "General_Island": ("Island", "Île"),
    "General_AtRest": ("Show the island when nothing happens", "Afficher l'île quand rien ne se passe"),
    "General_AtRest_Detail": (
        "Off, the island only comes out when something happens, or when you rest the pointer at the top edge of the screen.",
        "Désactivé, l'île ne sort que quand il se passe quelque chose, ou quand vous posez le pointeur sur le bord haut de l'écran.",
    ),
    "General_Hover": ("Open on hover", "Ouvrir au survol"),
    "General_Hover_Detail": (
        "Rest the pointer on the island to open it. Off, a click opens it.",
        "Posez le pointeur sur l'île pour l'ouvrir. Désactivé, un clic l'ouvre.",
    ),
    "General_Size": ("Size", "Taille"),
    "General_Size_Detail": ("How big the island is, closed and open.", "La taille de l'île, fermée et ouverte."),
    "Size_Compact": ("Compact", "Compacte"),
    "Size_Standard": ("Standard", "Standard"),
    "Size_Large": ("Large", "Grande"),
    "General_Display": ("Display", "Écran"),
    "General_Display_Detail": (
        "The island sits at the top centre of this display.",
        "L'île se place en haut au centre de cet écran.",
    ),
    "General_Display_Primary": ("Main display", "Écran principal"),
    "General_Display_Number": ("Display {0}, {1} × {2}", "Écran {0}, {1} × {2}"),
    "General_Display_IsPrimary": ("main", "principal"),
    "General_Shows": ("What the island shows", "Ce que l'île affiche"),
    "General_Volume": ("Volume", "Volume"),
    "General_Volume_Detail": (
        "A gauge in the island when the volume changes. Windows' own volume flyout still shows.",
        "Une jauge dans l'île quand le volume change. Le volume de Windows s'affiche toujours aussi.",
    ),
    "General_Battery": ("Battery and charging", "Batterie et charge"),
    "General_Battery_Detail": (
        "When the charger is plugged in or out, and when the battery runs low.",
        "Quand le chargeur est branché ou débranché, et quand la batterie est faible.",
    ),
    "General_Clipboard": ("Clipboard history", "Historique du presse-papiers"),
    "General_Clipboard_Detail": (
        "Your last text copies on the Tools page, kept in memory only and never written to disk. "
        "Copies that password managers mark as private are skipped.",
        "Vos dernières copies de texte dans la page Outils, gardées en mémoire seulement, jamais écrites sur le disque. "
        "Les copies que les gestionnaires de mots de passe marquent comme privées sont ignorées.",
    ),
    "Music_NowPlaying": ("Now playing", "À l'écoute"),
    "Music_NowPlaying_Detail": (
        "The song playing in Spotify, your browser or any app in Windows' media controls, with its cover and controls.",
        "Le morceau qui joue dans Spotify, votre navigateur ou toute app des commandes multimédias de Windows, avec sa pochette et ses commandes.",
    ),
    "Music_Lyrics": ("Lyrics", "Paroles"),
    "Music_SyncedLyrics": ("Synced lyrics", "Paroles synchronisées"),
    "Music_SyncedLyrics_Detail": (
        "The words of the song beside the player, line by line. Col asks LRCLIB, an open lyrics database: only the title, "
        "the artist, the album and the length of the song are sent, and the answer is kept on this PC.",
        f"Les paroles à côté du lecteur, ligne par ligne. Col les demande à LRCLIB, une base de paroles ouverte{NB}: seuls "
        "le titre, l'artiste, l'album et la durée du morceau sont envoyés, et la réponse est gardée sur ce PC.",
    ),
    "Music_LineClosed": ("Current line in the closed island", "Ligne en cours dans l'île fermée"),
    "Music_LineClosed_Detail": (
        "The line being sung, between the cover and the equalizer.",
        "La ligne chantée, entre la pochette et l'égaliseur.",
    ),
    "Music_Cache": ("Lyrics kept on this PC", "Paroles gardées sur ce PC"),
    "Music_Cache_Detail": ("{0} songs, {1} KB", f"{{0}} morceaux, {{1}}{NB}Ko"),
    "Music_Clear": ("Clear", "Effacer"),
    "Agents_Intro": (
        "Claude Code and Codex show in the island while they work. When one asks for permission, the island opens with the "
        "whole command, Allow and Deny. Col never signs in to any AI service.",
        "Claude Code et Codex s'affichent dans l'île pendant qu'ils travaillent. Quand l'un demande une permission, l'île "
        "s'ouvre avec la commande entière, Autoriser et Refuser. Col ne se connecte à aucun service d'IA.",
    ),
    "Agents_Connect": ("Connect", "Connecter"),
    "Agents_Disconnect": ("Disconnect", "Déconnecter"),
    "Agents_Connected": ("Connected", "Connecté"),
    "Agents_NotConnected": ("Not connected", "Non connecté"),
    "Agents_NotFound": ("Not found on this PC", "Introuvable sur ce PC"),
    "Agents_Backup": (
        "Col adds its hooks beside yours, keeps a copy of the file it edits (.col-backup) and leaves the rest untouched. "
        "Codex asks you to trust new hooks once, with /hooks.",
        "Col ajoute ses hooks à côté des vôtres, garde une copie du fichier modifié (.col-backup) et ne touche à rien "
        "d'autre. Codex vous demande une fois de faire confiance aux nouveaux hooks, avec /hooks.",
    ),
    "Agents_Scripts": ("Scripts and other agents", "Scripts et autres agents"),
    "Agents_Colctl_Detail": (
        "Your scripts put their own live activities in the island with the colctl command, from PowerShell, cmd or Git Bash.",
        "Vos scripts mettent leurs propres activités dans l'île avec la commande colctl, depuis PowerShell, cmd ou Git Bash.",
    ),
    "Agents_Colctl_Path": ("Installed at {0}", "Installé dans {0}"),
    "Agents_Colctl_Missing": (
        "colctl.exe is not beside Col.exe: reinstall Col to connect agents.",
        f"colctl.exe n'est pas à côté de Col.exe{NB}: réinstallez Col pour connecter les agents.",
    ),
    "About_Name": ("Col for Windows", "Col pour Windows"),
    "About_Version": ("Version {0}, preview", "Version {0}, aperçu"),
    "About_Tagline": ("A Dynamic Island at the top of your screen.", "Une Dynamic Island en haut de votre écran."),
    "About_License": ("Free and open source, under the MIT License.", "Libre et gratuit, sous licence MIT."),
    "About_Website": ("Website", "Site web"),
    "About_Source": ("Source code", "Code source"),
    "About_Changelog": ("What's new", "Nouveautés"),
    "About_Issues": ("Report a problem", "Signaler un problème"),
    "About_Privacy": ("Privacy", "Confidentialité"),
    "About_Privacy_Detail": (
        "No account, no telemetry, no analytics. Col only goes on the network to ask LRCLIB for lyrics, while synced "
        "lyrics are on. Scripts and agents reach Col through a pipe only your account can open.",
        "Pas de compte, pas de télémétrie, pas de statistiques. Col ne va sur le réseau que pour demander des paroles à "
        "LRCLIB, tant que les paroles synchronisées sont activées. Scripts et agents joignent Col par un canal que seul "
        "votre compte peut ouvrir.",
    ),
    "About_Unsigned": ("An unsigned preview", "Un aperçu non signé"),
    "About_Unsigned_Detail": (
        "This preview is not signed with a code-signing certificate yet, so Windows SmartScreen may warn before the first "
        "launch: choose More info, then Run anyway.",
        f"Cet aperçu n'est pas encore signé par un certificat de signature de code, Windows SmartScreen peut donc avertir "
        f"avant le premier lancement{NB}: choisissez Informations complémentaires, puis Exécuter quand même.",
    ),
    "About_Credits": (
        "The logos of coding agents come from LobeHub Icons (MIT) and belong to their owners.",
        "Les logos des agents de code viennent de LobeHub Icons (MIT) et appartiennent à leurs propriétaires.",
    ),
}

HEADER = """<?xml version="1.0" encoding="utf-8"?>
<!-- Written by windows/tools/strings.py: edit the words there. -->
<root>
  <resheader name="resmimetype"><value>text/microsoft-resx</value></resheader>
  <resheader name="version"><value>2.0</value></resheader>
  <resheader name="reader"><value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value></resheader>
  <resheader name="writer"><value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value></resheader>
"""


def write(path: Path, index: int) -> None:
    lines = [HEADER]
    for key, values in STRINGS.items():
        text = values[index]
        assert "—" not in text, f"{key}: no em dash"
        lines.append(f'  <data name="{key}" xml:space="preserve"><value>{escape(text)}</value></data>\n')
    lines.append("</root>\n")
    path.write_text("".join(lines), encoding="utf-8")


if __name__ == "__main__":
    folder = Path(__file__).resolve().parent.parent / "src" / "Col" / "Resources"
    folder.mkdir(parents=True, exist_ok=True)
    write(folder / "Strings.resx", 0)
    write(folder / "Strings.fr.resx", 1)
    print(f"{len(STRINGS)} strings")
