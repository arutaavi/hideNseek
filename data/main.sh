#!/bin/bash

# ==================================================
# VEATU KUVAMINE JA TAUSTA LUKUSTUS
# ==================================================
tput smcup
export NEWT_COLORS='
root=white,blue
back=white,blue
title=white,blue
roottext=white,blue
window=white,lightgray
border=black,lightgray
shadow=black,black
button=white,blue
actbutton=white,cyan
'

cleanup() {
    clear
    tput rmcup
}
trap cleanup EXIT
export NCURSES_NO_UTF8_ACS=1

# ==================================================
# ASUKOHAD JA MUUTUJAD
# ==================================================
SKRIPTI_ASUKOHT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_KAUST="$SKRIPTI_ASUKOHT/input"
VAVALIK_FAIL="$INPUT_KAUST/vars.yml"
VSALAJANE_FAIL="$INPUT_KAUST/vault.yml"
PLAYBOOK_FAIL="$SKRIPTI_ASUKOHT/elasticsearch.yml"
VAULT_VOTI="/root/.hidenseek_vault"
SEADISTUS_LIPP="$INPUT_KAUST/.seadistus_tehtud"

mkdir -p "$INPUT_KAUST"

# ==================================================
# ABIFUNKTSIOON: UUENDAB VÕI LISAB MUUTUJA FAILIS
# ==================================================
uuenda_muutuja() {
    local fail="$1"
    local voti="$2"
    local vaartus="$3"

    # Kui faili pole, loome uue
    if [ ! -f "$fail" ] || [ ! -s "$fail" ]; then
        echo "---" > "$fail"
    fi

    # Muudab ainult vastava muutuja rida (kommentaarid jäävad alles)
    if grep -q "^${voti}:" "$fail"; then
        sed -i "s|^${voti}:.*|${voti}: \"${vaartus}\"|" "$fail"
    else
        echo "${voti}: \"${vaartus}\"" >> "$fail"
    fi
}

# ==================================================
# SÜSTEEMI ANDMETE TUVASTUS (Kasutajaliidese jaoks)
# ==================================================
tuvasta_vorgud() {
    REALSED_LIIDESED=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|docker|veth|br-|any|loop')
    whiptail_lahendus=()
    POHI_INT=$(ip route show default | awk '{print $5}' | head -n 1)

    for int in $REALSED_LIIDESED; do
        ip_olemas=$(ip -br addr show dev "$int" | awk '{print $3}')
        [ ! -z "$ip_olemas" ] && kirjeldus="Aktiivne ($ip_olemas)" || kirjeldus="IP puudub"
        [ "$int" == "$POHI_INT" ] && whiptail_lahendus+=("$int" "$kirjeldus" "ON") || whiptail_lahendus+=("$int" "$kirjeldus" "OFF")
    done

    VAIKIMISI_NET=""
    if [ ! -z "$POHI_INT" ]; then
        IP_JA_MASK=$(ip -o -4 addr show dev "$POHI_INT" | awk '{print $4}' | head -n 1)
        if [ ! -z "$IP_JA_MASK" ]; then
            ip_osa=$(echo "$IP_JA_MASK" | cut -d'/' -f1)
            mask_osa=$(echo "$IP_JA_MASK" | cut -d'/' -f2)
            VAIKIMISI_NET="$(echo "$ip_osa" | sed 's/\.[0-9]*$/\.0/')/${mask_osa}"
        fi
    fi
    [ -z "$VAIKIMISI_NET" ] && VAIKIMISI_NET="192.168.1.0/24"
}

# ==================================================
# SISENDITE KÜSIMISE BLOKID
# ==================================================
kysi_avalikud_seaded() {
    tuvasta_vorgud

    local valitud_ints=$(whiptail --title "Võrguliideste valik" --checklist \
    "Vali märkmeruudud (TÜHIKUGA) liidestest, mida Suricata/Arkime kuulama peavad:" 15 65 6 "${whiptail_lahendus[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    valitud_ints=$(echo "$valitud_ints" | sed 's/"//g' | sed 's/ /,/g')
    [ -z "$valitud_ints" ] && { whiptail --title "Viga" --msgbox "Sa pead valima vähemalt ühe liidese!" 8 50; return 1; }

    local home=$(whiptail --title "Sisevõrgu aadressiruum" --inputbox "Sisesta oma koduvõrk/sisevõrk (erinevad eralda komaga):" 11 60 "$VAIKIMISI_NET" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    [ -z "$home" ] && { whiptail --title "Viga" --msgbox "Sisevõrk ei tohi olla tühi!" 8 50; return 1; }

    local ram=""
    while [[ ! "$ram" =~ ^[0-9]+$ ]]; do
        ram=$(whiptail --title "Elasticsearch RAM" --inputbox "Mitu GB muutmälu eraldad Elasticsearchile? (ainult number)" 11 60 "4" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && return 1
        [[ ! "$ram" =~ ^[0-9]+$ ]] && whiptail --title "Viga" --msgbox "Palun sisesta ainult täisarv!" 8 50
    done

    # Kirjutame avalikud andmed (luku maha ja tagasi peale, kui fail on lukus)
    [ -f "$VAVALIK_FAIL" ] && chattr -i "$VAVALIK_FAIL" > /dev/null 2>&1
    uuenda_muutuja "$VAVALIK_FAIL" "monitor_ints" "$valitud_ints"
    uuenda_muutuja "$VAVALIK_FAIL" "home_net" "$home"
    uuenda_muutuja "$VAVALIK_FAIL" "elastic_ram" "${ram}g"
    chmod 600 "$VAVALIK_FAIL"
    chattr +i "$VAVALIK_FAIL" > /dev/null 2>&1
    return 0
}

kysi_yks_parool() {
    local tiitel="$1"
    local tekst="$2"
    local muutuja_nimi="$3"

    local uus_pwd=$(whiptail --title "$tiitel" --passwordbox "$tekst" 10 60 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] || [ -z "$uus_pwd" ] && return 1

    # Avame luku ja dekrüpteerime ajutiselt (kui on juba krüpteeritud)
    [ -f "$VSALAJANE_FAIL" ] && chattr -i "$VSALAJANE_FAIL" > /dev/null 2>&1
    if [ -f "$VSALAJANE_FAIL" ] && grep -q "\$ANSIBLE_VAULT" "$VSALAJANE_FAIL" 2>/dev/null; then
        ansible-vault decrypt "$VSALAJANE_FAIL" --vault-password-file "$VAULT_VOTI" > /dev/null 2>&1
    fi

    # Uuendame ainult seda ühte rida
    uuenda_muutuja "$VSALAJANE_FAIL" "$muutuja_nimi" "$uus_pwd"

    # Krüpteerime uuesti ja paneme luku peale
    if [ -f "$VAULT_VOTI" ]; then
        sed -i 's/\$ANSIBLE_VAULT;//g' "$VSALAJANE_FAIL" 2>/dev/null
        ansible-vault encrypt "$VSALAJANE_FAIL" --vault-password-file "$VAULT_VOTI" > /dev/null 2>&1
    fi
    chmod 600 "$VSALAJANE_FAIL"
    chattr +i "$VSALAJANE_FAIL" > /dev/null 2>&1

    whiptail --title "Edukalt muudetud" --msgbox "Parool on uuendatud ja fail uuesti krüpteeritud/lukustatud." 8 60
}

# ==================================================
# ALAMMENÜÜD JA ESMANE SEADISTUS
# ==================================================
esmane_seadistus() {
    whiptail --title "Esmane seadistus" --msgbox "Tundub, et seadistad süsteemi esimest korda.\n\nPalun vasta viiele küsimusele, et luua turvalised andmefailid." 10 60

    kysi_avalikud_seaded || return
    kysi_yks_parool "Elasticsearchi parool" "Määra parool Elasticsearchi superkasutajale 'elastic':" "elastic_pwd" || return
    kysi_yks_parool "Veebiliideste parool" "Määra parool Arkime ja EveBoxi administraatorile 'admin':" "arkime_pwd" || return

    # Märgime esmase seadistuse tehtuks
    touch "$SEADISTUS_LIPP"

    whiptail --title "Süsteem lukustatud" --msgbox "Kõik andmed on sisestatud!\n\nFailidele rakendati turvaline 'chattr +i' lukustus. Avalikud seaded ja krüpteeritud paroolid on turvaliselt eraldatud." 12 65
}

muuda_paroole_menyy() {
    while true; do
        VALIK=$(whiptail --title "Muuda paroole" --menu "Millist parooli soovid muuta?" 15 60 3 \
        "1" "Muuda Elasticsearchi parooli" \
        "2" "Muuda Arkime/EveBox parooli" \
        "3" "Tagasi" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ] || [ "$VALIK" == "3" ]; then break; fi

        case "$VALIK" in
            "1") kysi_yks_parool "Elasticsearchi parool" "Sisesta UUS parool kasutajale 'elastic':" "elastic_pwd" ;;
            "2") kysi_yks_parool "Veebiliideste parool" "Sisesta UUS parool kasutajale 'admin':" "arkime_pwd" ;;
        esac
    done
}

sisendite_haldus() {
    # Tuvastame lipufaili järgi, kas on esmakordne sisenemine
    if [ ! -f "$SEADISTUS_LIPP" ]; then
        esmane_seadistus
        return
    fi

    # Kui andmed on juba olemas, näitame jaotatud alammenüüd
    while true; do
        ALAMVALIK=$(whiptail --title "Sisendite Haldus" --menu "Mida soovid teha?" 15 60 4 \
        "1" "Kuva praegused sätted" \
        "2" "Muuda sätteid" \
        "3" "Muuda paroole" \
        "4" "Tagasi" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ] || [ "$ALAMVALIK" == "4" ]; then break; fi

        case "$ALAMVALIK" in
            "1")
                # Kuvab ainult avalikud seaded
                SISU=$(cat "$VAVALIK_FAIL")
                whiptail --title "Praegused avalikud seaded" --msgbox "$SISU\n\n(Paroole ei kuvata turvalisuse kaalutlustel)" 15 60
                ;;
            "2")
                # Käivitab avalike seadete (võrgud, RAM jne) muutmise jada
                kysi_avalikud_seaded
                [ $? -eq 0 ] && whiptail --title "Edukalt muudetud" --msgbox "Avalikud sätted on uuendatud ja lukustatud." 8 60
                ;;
            "3")
                # Avab eraldi menüü ainult paroolide muutmiseks
                muuda_paroole_menyy
                ;;
        esac
    done
}

# ==================================================
# PAIGALDUSE KÄIVITAMINE (ANSIBLE)
# ==================================================
kaivita_paigaldus() {
    if [ ! -f "$SEADISTUS_LIPP" ]; then
        whiptail --title "Viga" --msgbox "Paigaldust ei saa alustada, sest sisendid on seadistamata!\n\nPalun vali esmalt menüüst 'Sisendid'." 10 60
        return
    fi

    {
        echo 10; echo "XXX\nValmistame Ansible keskkonda ette...\nXXX"; sleep 1
        echo 25; echo "XXX\nRakendame konfiguratsiooni. Muudetakse ainult neid teenuseid, mille seaded muutusid.\n(See võib võtta aega)\nXXX"

        ansible-playbook "$PLAYBOOK_FAIL" \
            --vars-file "$VAVALIK_FAIL" \
            --vars-file "$VSALAJANE_FAIL" \
            --vault-password-file "$VAULT_VOTI" > /var/log/hidenseek_ansible.log 2>&1
        ANSIBLE_STATUS=$?

        if [ $ANSIBLE_STATUS -eq 0 ]; then
            echo 90; echo "XXX\nSeadistused edukalt rakendatud! Teeme viimaseid tervisekontrolle...\nXXX"; sleep 2
            echo 100; echo "XXX\nKõik valmis!\nXXX"; sleep 1
        else
            echo "VIGA" > "$INPUT_KAUST/.error_flag"
        fi
    } | whiptail --title "SOC Paigaldamine" --gauge "Alustame..." 12 65 0

    if [ -f "$INPUT_KAUST/.error_flag" ]; then
        rm -f "$INPUT_KAUST/.error_flag"
        whiptail --title "PAIGALDUS EBAÕNNESTUS" --msgbox "Ansible tegi vea! Teenuseid ei saanud korrektselt seadistada.\n\nTäpsemat logi saad vaadata käsuga:\ncat /var/log/hidenseek_ansible.log" 12 65
    else
        whiptail --title "EDUKAS" --msgbox "SOC seadistused on rakendatud! Idempotentsus tagas, et serveri ressurssi ei raisatud asjatult." 10 65
    fi
}

# ==================================================
# PEAMENÜÜ TSÜKKEL
# ==================================================
while true; do
    VALIK=$(whiptail --title "hideNseek SOC Haldus" --menu "Kasuta nooli ja Enterit valiku tegemiseks:" 15 60 3 \
    "Sisendid" "Seadista võrgud, liidesed ja paroolid" \
    "Paigaldus" "Käivita teenuste paigaldamine ja uuendamine" \
    "Exit" "Sulge programm" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then break; fi

    case "$VALIK" in
        "Sisendid") sisendite_haldus ;;
        "Paigaldus") kaivita_paigaldus ;;
        "Exit") break ;;
    esac
done