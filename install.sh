#!/bash/bin

# Funktsioon "Teade ja väljumine" vigade puhul
exit_with_error() {
    local veateade="$1"
    whiptail --title "VIGA" --msgbox "$veateade\n\nPaigaldus katkestati." 10 60
    clear
    exit 1
}

# ==================================================
# ALUSTAMINE JA KINNITUS
# ==================================================
whiptail --title "hideNseek SOC Paigaldus" --yesno \
"Tere tulemast hideNseek esmasesse paigaldusse!\n\nKas soovid alustada süsteemi ettevalmistamist ja komponentide kontrolli?" 12 65

if [ $? -ne 0 ]; then
    clear
    exit 0
fi

# ==================================================
# 1. ETAPP: KOHALIKUD KONTROLLID (Õigused ja Failid)
# ==================================================

# 1.1 Root õiguste kontroll
if [ "$EUID" -ne 0 ]; then
    exit_with_error "Skripti käivitamiseks on vaja sudo õigusi!\n\nPalun käivita skript käsuga: sudo ./install.sh"
fi

# 1.2 "data" kausta kontroll (Tõstetud siia, et vältida asjatut paigaldust!)
if [ ! -d "./data" ]; then
    exit_with_error "Ei leidnud vajalikku kausta 'data'!\n\nVeendu, et oled kõik failid mälupulgalt või arhiivist korrektselt lahti pakkinud ja käivitad install.sh faili otse selle õigest algkaustast."
fi

# ==================================================
# 2. ETAPP: VÕRGU KONTROLL
# ==================================================
whiptail --title "Võrgu kontroll" --infobox "Kontrollime internetiühenduse olemasolu..." 8 50
sleep 1

if ! ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
    exit_with_error "Süsteemil puudub internetiühendus!\n\nAnsible ja vajalike pakettide allalaadimiseks on vaja toimivat võrku.\n\nHyper-V puhul kontrolli, et masinal oleks küljes 'External' või 'Default Switch' tüüpi virtuaallüliti."
fi

# ==================================================
# 3. ETAPP: ANSIBLE KONTROLL JA PAIGALDUS
# ==================================================
if command -v ansible-playbook &> /dev/null; then
    ANSIBLE_VER=$(ansible --version | head -n 1 | awk '{print $2}')
    whiptail --title "Ansible Kontroll" --msgbox "Ansible on juba süsteemis olemas!\nTuvastatud versioon: $ANSIBLE_VER\n\nLiigume edasi failide kopeerimise juurde." 10 60
else
    whiptail --title "Ansible Puudub" --yesno \
    "hideNseek paigaldamiseks on vaja Ansiblet, kuid seda ei leitud.\n\nKas lubad skriptil paigaldada Ansible automaatselt ametlikust PPA repositooriumist?" 12 65

    if [ $? -eq 0 ]; then
        {
            echo 10; echo "XXX\nUuendame süsteemi pakettide nimekirja...\nXXX"
            apt-get update -y > /dev/null 2>&1

            echo 30; echo "XXX\nPaigaldame vajalikud tugitööriisad (curl, git, whiptail)...\nXXX"
            apt-get install -y software-properties-common curl git whiptail > /dev/null 2>&1

            echo 50; echo "XXX\nLisame Ansible ametliku PPA repositooriumi...\nXXX"
            apt-add-repository -y ppa:ansible/ansible > /dev/null 2>&1

            echo 70; echo "XXX\nUuendame uue repositooriumi andmeid...\nXXX"
            apt-get update -y > /dev/null 2>&1

            echo 90; echo "XXX\nAlustame Ansible põhipaketi paigaldamist...\nXXX"
            apt-get install -y ansible > /dev/null 2>&1

            echo 100; echo "XXX\nAnsible paigaldus on lõpetatud!\nXXX"
            sleep 1
        } | whiptail --title "Ansible Paigaldamine" --gauge "Palun oota, valmistame süsteemi ette..." 10 60 0

        if ! command -v ansible-playbook &> /dev/null; then
            exit_with_error "Midagi läks Ansible paigaldamisel valesti.\nPalun kontrolli internetiühendust ja apt repositooriume."
        fi
    else
        exit_with_error "Paigaldus katkestati, kuna Ansiblet ei lubatud paigaldada."
    fi
fi

# ==================================================
# 4. ETAPP: SCRIPTIDE KOPEERIMINE ETTENÄHTUD KAUSTA
# ==================================================
SIHTKAUST="/usr/share/hidenseek"

whiptail --title "Failide kopeerimine" --infobox "Kopeerime Ansible skripte asukohta:\n$SIHTKAUST ..." 8 60

mkdir -p "$SIHTKAUST"
cp -r ./data/* "$SIHTKAUST/"

if [ $? -ne 0 ]; then
    exit_with_error "Failide kopeerimine sihtkausta ebaõnnestus. Kontrolli ketta vaba ruumi."
fi
sleep 1

# ==================================================
# 5. ETAPP: GLOBAALSE KÄSU JA VAULTI LOOMINE
# ==================================================
whiptail --title "Seadistamine" --infobox "Luukse süsteemseid käske ja krüptovõtmeid..." 8 60

VAULT_VOTI="/root/.hidenseek_vault"
if [ ! -f "$VAULT_VOTI" ]; then
    openssl rand -base64 32 > "$VAULT_VOTI"
    chmod 600 "$VAULT_VOTI"
fi

KASU_FAIL="/usr/local/bin/hidenseek"

cat <<EOF > "$KASU_FAIL"
#!/bin/bash
cd $SIHTKAUST
sudo ./main.sh "\$@"
EOF

chmod +x "$KASU_FAIL"
chmod +x "$SIHTKAUST/main.sh"

if [ ! -f "$KASU_FAIL" ]; then
    exit_with_error "Globaalse käsu 'hidenseek' loomine ebaõnnestus."
fi
sleep 1

# ==================================================
# LÕPETAMINE
# ==================================================
whiptail --title "PAIGALDUS EDUKAS!" --msgbox \
"hideNseek esmane ettevalmistus on edukalt tehtud!\n\nKõik skriptid on turvaliselt kopeeritud süsteemi.\n\nSelle esmase kausta võid mälupulgalt või kodukaustast nüüd ära kustutada.\n\nSOC halduskeskkonna käivitamiseks kirjuta terminalis:\n\nhidenseek" 16 65

clear