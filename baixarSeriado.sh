#!/bin/bash

#Parametros sobre o seriado
#Caso nao seja informado via parametro para o script, os valores abaixo serao utilizados
SERIADO="Game of Thrones"
SERIADO_ABREVIADO="GOT"
TEMPORADA=06
EPISODIO=08

#Parametros sobre o Pirate Bay
PIRATE_BAY_SEARCH_URL="https://thepiratebay.se/search"
#Altere os padrões de busca no Pirate Bay, separando as palavras chave por ;
PADROES_TORRENT=()

#Parametros sobre o Transmission (Torrent downloader)
TRANSMISSION_USER_PASS="transmission:transmission"
TRANSMISSION_DOWNLOAD_FOLDER="/var/lib/transmission-daemon/downloads"

#Parametros sobre o OpenSubtitles
OPENSUBTITLES_USER=""
OPENSUBTITLES_PASS=""
OPENSUBTITLES_AGENT=""

#Parametros sobre o LegendasTV
LEGENDASTV_URL="http://legendas.tv"
LEGENDASTV_USER=""
LEGENDASTV_PASS=""
#LEGENDASTV_TEMPORADA="Game of Thrones - 6a Temporada"
LEGENDASTV_TEMPORADA=""

#Pasta onde todos os arquivos serao criados e salvos
#Não altere nada daqui para baixo
PASTA_DESTINO=""
PASTA_TORRENT=""
PASTA_LEGENDA=""
PASTA_LOG=""
PASTA_TEMPORARIO=""
ARQUIVO_LOG=""
URL_MAGNET=""
BAIXAR_VIDEO="SIM"
BAIXAR_LEGENDA="SIM"


urlencode() {
    # urlencode <string>
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C
    
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
    
    LC_COLLATE=$old_lc_collate
}

moverTorrent() {
	NOME_TORRENT=$(transmission-remote -n ${TRANSMISSION_USER_PASS} -t $1 -i | grep "Name: " | cut -d":" -f2 | cut -c2-)
	#transmission-remote -n ${TRANSMISSION_USER_PASS} -t $1 --move "${PASTA_DESTINO}"
	transmission-remote -n ${TRANSMISSION_USER_PASS} -t $1 --remove >/dev/null
	
	$(find ${TRANSMISSION_DOWNLOAD_FOLDER}/${NOME_TORRENT} -iname "*.mkv" -type f -exec cp "{}" ${PASTA_TORRENT} \;)
	$(find ${TRANSMISSION_DOWNLOAD_FOLDER}/${NOME_TORRENT} -iname "*.mp4" -type f -exec cp '{}' ${PASTA_TORRENT} \;)
	$(find ${TRANSMISSION_DOWNLOAD_FOLDER}/${NOME_TORRENT} -iname "*.avi" -type f -exec cp '{}' ${PASTA_TORRENT} \;)
}

aguardarDownloadTorrent() {
	sleep 1m
	CONCLUIDO=1
	while [ ${CONCLUIDO} -eq 1 ] 
	do
		TORRENTLIST=$(transmission-remote -n ${TRANSMISSION_USER_PASS} -l | sed -e '1d;$d;s/^ *//' | cut --only-delimited --delimiter=" "  --fields=1)
		echo -ne "$(date) - Aguardando finalizacao do torrent..." >> ${ARQUIVO_LOG}	
		for TORRENTID in $TORRENTLIST; do
			if transmission-remote -n ${TRANSMISSION_USER_PASS} -t ${TORRENTID} -i | grep "Percent Done: 100%" >/dev/null; then
				echo "100% concluido" >> ${ARQUIVO_LOG}
				moverTorrent $TORRENTID
				CONCLUIDO=0
			else
				PER_CONC=$(transmission-remote -n ${TRANSMISSION_USER_PASS} -t ${TORRENTID} -i | grep "Percent Done:" | cut -d":" -f2 | cut -c2-)
				echo "${PER_CONC} concluido" >> ${ARQUIVO_LOG}
				sleep 1m
			fi
		done
		
	done
}

verificarDisponibilidadeTorrent() {
	for PADRAO_TORRENT in "${PADROES_TORRENT[@]}"; do
		PADRAO_TORRENT=$(echo ${PADRAO_TORRENT} | tr ';' ' ')
		echo -ne "$(date) - Procurando ${SERIADO} S${TEMPORADA}E${EPISODIO} ${PADRAO_TORRENT} no Pirate Bay..." >> ${ARQUIVO_LOG}
		URL_BUSCA="${PIRATE_BAY_SEARCH_URL}/"$(urlencode "${SERIADO} s${TEMPORADA}e${EPISODIO} ${PADRAO_TORRENT}")
			
		wget ${URL_BUSCA} -O "${PASTA_TEMPORARIO}/saida.html" -o /dev/null
		if cat "${PASTA_TEMPORARIO}/saida.html" | grep '<a href="magnet' >/dev/null; then
			echo "encontrado" >> ${ARQUIVO_LOG}
	        	URL_MAGNET=`cat "${PASTA_TEMPORARIO}/saida.html" | grep '<a href="magnet' | cut -d'"' -f2`
			return 0
		else
			echo "nao encontrado" >> ${ARQUIVO_LOG}
		fi

	done
	return 1

}

baixarEpisodio() {
	echo -ne "Baixando o episódio..."
	while [ 1 ]
	do
		if verificarDisponibilidadeTorrent; then
			echo "$(date) - Iniciando download do ${SERIADO} S${TEMPORADA}E${EPISODIO}" >> ${ARQUIVO_LOG}
			#echo ${URL_MAGNET}
			#transmission-cli ${URL_MAGNET} -w ${PASTA_DESTINO}
			transmission-remote -n 'transmission:transmission' -a ${URL_MAGNET} >/dev/null
			aguardarDownloadTorrent
			echo "$(date) - Download do torrent finalizado" >> ${ARQUIVO_LOG}
			break
		fi
		echo "$(date) - Nada por enquanto, aguardando 10 minutos..." >> ${ARQUIVO_LOG}
		sleep 10m
	done
	echo "concluido"
}

buscarLegenda_LegendasTV() {
	echo "Baixando a legenda..."
	CONCLUIDO=1
	while [ ${CONCLUIDO} -eq 1 ]
	do
		#Autenticar no LegendasTV
		echo "$(date) - Autenticando no LegendasTV..." >> ${ARQUIVO_LOG}
		if [ ! -f "${PASTA_TEMPORARIO}/cookies.txt" ]; then
			LEGENDASTV_PASS_ENCODED=$(urlencode ${LEGENDASTV_PASS})
			wget --save-cookies "${PASTA_TEMPORARIO}/cookies.txt" \
	    		--post-data '_method=POST&data%5BUser%5D%5Busername%5D='${LEGENDASTV_USER}'&data%5BUser%5D%5Bpassword%5D='${LEGENDASTV_PASS_ENCODED}'&data%5Blembrar%5D=on' \
			http://legendas.tv/login -o /dev/null -O "${PASTA_TEMPORARIO}/login.html"
		fi

		if ! grep legendas.tv "${PASTA_TEMPORARIO}/cookies.txt" 1>/dev/null 2>/dev/null; then
			echo "Nao foi possivel se autenticar no Legendas.tv, verifique usuario e senha e a disponibilidade do site e conexao..." >> ${ARQUIVO_LOG}
			rm "${PASTA_TEMPORARIO}/cookies.txt"
			exit 1
		fi

		#Pesquisar pelo seriado no Legendas TV
		echo "$(date) - Pesquisando ${SERIADO} no LegendasTV..." >> ${ARQUIVO_LOG}
		wget --load-cookies "${PASTA_TEMPORARIO}/cookies.txt" \
		http://legendas.tv/busca/$(urlencode "${SERIADO}") -O "${PASTA_TEMPORARIO}/temporadas.html" -o /dev/null

		LEGENDASTV_TEMPORADA="${SERIADO} - $(echo "${TEMPORADA}+0"|bc)a Temporada"
		#Buscar ID de busca da temporada
		TEMPORADA_ID=$(awk -v tgt="${LEGENDASTV_TEMPORADA}" 'IGNORECASE=1;BEGIN{RS="</a>"; ORS=RS"\n"; tgt=""tgt"</p>"} $0 ~ tgt' "${PASTA_TEMPORARIO}/temporadas.html"  | grep -i "${LEGENDASTV_TEMPORADA}" | grep -o data-filme=.* | cut -d '"' -f2 | head -n1)
		
		#Se não encontrou com "a", tenta com "ª"		
		if [ ${#TEMPORADA_ID} -eq 0 ]; then
			LEGENDASTV_TEMPORADA="${SERIADO} - $(echo "${TEMPORADA}+0"|bc)ª Temporada"
			#Buscar ID de busca da temporada
			TEMPORADA_ID=$(awk -v tgt="${LEGENDASTV_TEMPORADA}" 'IGNORECASE=1;BEGIN{RS="</a>"; ORS=RS"\n"; tgt=""tgt"</p>"} $0 ~ tgt' "${PASTA_TEMPORARIO}/temporadas.html"  | grep -i "${LEGENDASTV_TEMPORADA}" | grep -o data-filme=.* | cut -d '"' -f2 | head -n1)
		fi

		if [ ${#TEMPORADA_ID} -eq 0 ]; then
			echo "Temporada nao encontrada" >> ${ARQUIVO_LOG}
			echo "$(date) - Aguardando ate a proxima verificação (5 minutos)" >> ${ARQUIVO_LOG}
			sleep 5m
			continue
		fi

		#Buscar todas as legendas disponiveis para a temporada e verificar se já está disponível a versão a do episodio informado
		echo -ne "$(date) - Verificando se a legenda para o S${TEMPORADA}E${EPISODIO} ja esta disponivel..." >> ${ARQUIVO_LOG}
		wget --load-cookies "${PASTA_TEMPORARIO}/cookies.txt" http://legendas.tv/legenda/busca/-/1/-/0/${TEMPORADA_ID} -O "${PASTA_TEMPORARIO}/legendas.html" -o /dev/null
		LEGENDA_DOWNLOAD_PAGINA=$(cat "${PASTA_TEMPORARIO}/legendas.html" | grep -o '/download/[^"]*' | grep S${TEMPORADA}E${EPISODIO})

		#Baixar todas as legendas disponíveis do episodio informado
		if [ ${#LEGENDA_DOWNLOAD_PAGINA} -ne 0 ]; then
			echo "encontrado" >> ${ARQUIVO_LOG}
			for legenda in ${LEGENDA_DOWNLOAD_PAGINA}; do
				if [ ${legenda} ]; then
					NOMEARQUIVO="$(echo ${legenda} | rev | cut -d"/" -f1 | rev ).rar"
					echo "$(date) - Baixando ${NOMEARQUIVO}..." >> ${ARQUIVO_LOG}
					wget --load-cookies "${PASTA_TEMPORARIO}/cookies.txt" ${LEGENDASTV_URL}${LEGENDA_DOWNLOAD_PAGINA} -O "${PASTA_TEMPORARIO}/download.html" -o /dev/null
					DOWNLOAD_URL=$(cat "${PASTA_TEMPORARIO}/download.html" | grep downloadarquivo | cut -d"'" -f2)
					wget --load-cookies "${PASTA_TEMPORARIO}/cookies.txt" ${LEGENDASTV_URL}${DOWNLOAD_URL} -O "${PASTA_LEGENDA}/${NOMEARQUIVO}" -o /dev/null
				fi
			done
			CONCLUIDO=0
		else
			echo "nao encontrado" >> ${ARQUIVO_LOG}
			echo "$(date) - Aguardando ate a proxima verificação (5 minutos)" >> ${ARQUIVO_LOG}
			sleep 5m
		fi
	done
	
	#Descompactar todos os arquivos de legenda	
	for legenda in `ls ${PASTA_LEGENDA}/*.rar`; do
		unrar e $legenda -o+ -inull "${PASTA_LEGENDA}" >/dev/null
	done
	echo "concluido"
}

buscarLegenda_OpenSubtitles() {
	echo "$(date) - Procurando legenda no OpenSubtitles" >> ${ARQUIVO_LOG}
	OPENSUBTITLES_LOGIN_XML="<methodCall><methodName>LogIn</methodName><params><param><value><string>${OPENSUBTITLES_USER}</string></value></param><param><value><string>${OPENSUBTITLES_PASS}</string></value></param><param><value><string>en</string></value></param><param><value><string>${OPENSUBTITLES_AGENT}</string></value></param></params></methodCall>"
	echo "${OPENSUBTITLES_LOGIN_XML}" > "${PASTA_TEMPORARIO}/os_login.xml"
	OPENSUBTITLES_TOKEN=$(curl --data "@${PASTA_TEMPORARIO}/os_login.xml" ​api.opensubtitles.org/xml-rpc 2>/dev/null | head -n 10 | tail -n 1 | cut -d'>' -f 2 | cut -d '<' -f 1)
	
	if [ ${#OPENSUBTITLES_TOKEN} -eq 0 ]; then
		echo "$(date) - Nao foi possivel se autenticar no OpenSubtitles" >> ${ARQUIVO_LOG}
		exit 2
	fi

	ARQUIVO_VIDEO="$(ls ${PASTA_TORRENT}/*.{mkv,mp4,avi} 2>/dev/null)"
	
	HASH=$( hash_file ${ARQUIVO_VIDEO} )
	SIZE=$( du -b ${ARQUIVO_VIDEO} | cut -f 1 )
	
	OPENSUBTITLES_SEARCH_XML="<methodCall><methodName>SearchSubtitles</methodName><params><param><value><string>${OPENSUBTITLES_TOKEN}</string></value></param><param><value><array><data><value><struct><member><name>sublanguageid</name><value><string>pob</string></value></member><member><name>moviehash</name><value><string>${HASH}</string></value></member><member><name>moviebytesize</name><value><double>${SIZE}</double></value></member></struct></value></data></array></value></param></params></methodCall>"
	echo "${OPENSUBTITLES_SEARCH_XML}" > "${PASTA_TEMPORARIO}/os_search.xml"
	$( curl --data "@${PASTA_TEMPORARIO}/os_search.xml" ​api.opensubtitles.org/xml-rpc 2>/dev/null 1> "${PASTA_TEMPORARIO}/search_results.xml" )

	LEGENDA_GZ=$( cat "${PASTA_TEMPORARIO}/search_results.xml" | grep .gz | cut -d '>' -f 2 | cut -d '<' -f 1 )
	
	if [ ${#LEGENDA_GZ} -ne 0 ]; then
		NOMEARQUIVO="$(echo ${ARQUIVO_VIDEO} | rev | cut -d"/" -f1 | cut -c5- | rev)"
		wget ${LEGENDA_GZ} -O "${PASTA_LEGENDA}/${NOMEARQUIVO}.gz" -o /dev/null
		gzip -dc "${PASTA_LEGENDA}/${NOMEARQUIVO}.gz" > "${PASTA_LEGENDA}/${NOMEARQUIVO}.srt"
		rm "${PASTA_LEGENDA}/${NOMEARQUIVO}.gz"
		echo "true"
	else
		echo "$(date) - Legenda nao encontrada no OpenSubtitles" >> ${ARQUIVO_LOG}
		echo "false"
	fi
	
}

iniciarTrabalhos() {
	#Verifica se todos os comandos necessario para rodar o script estao instalados	
	hash iconv 2>/dev/null || { echo >&2 "O comando iconv eh necessario mas parece que nao esta instalado.  Cancelando."; exit 1; }
	hash curl 2>/dev/null || { echo >&2 "O comando curl eh necessario mas parece que nao esta instalado.  Cancelando."; exit 1; }
	hash ffmpeg 2>/dev/null || { echo >&2 "O comando ffmpeg eh necessario mas parece que nao esta instalado.  Cancelando."; exit 1; }
	hash transmission-remote 2>/dev/null || { echo >&2 "O comando transmission-remote eh necessario mas parece que nao esta instalado.  Cancelando."; exit 1; }
	hash transmission-daemon 2>/dev/null || { echo >&2 "O comando transmission-daemon eh necessario mas parece que nao esta instalado.  Cancelando."; exit 1; }
	hash wget 2>/dev/null || { echo >&2 "O comando wget eh necessario mas parece que nao esta instalado.  Cancelando."; exit 1; }
	hash unrar 2>/dev/null || { echo >&2 "O comando unrar eh necessario mas parece que nao esta instalado.  Cancelando."; exit 1; }
	hash awk 2>/dev/null || { echo >&2 "O comando awk eh necessario mas parece que nao esta instalado.  Cancelando."; exit 1; }
	hash sed 2>/dev/null || { echo >&2 "O comando sed eh necessario mas parece que nao esta instalado.  Cancelando."; exit 1; }
	
	#Garante que se o usuario passar um numero sem zero a esquerda, ele sera colocado
	if [ ${TEMPORADA} -lt 10 ]; then
		TEMPORADA="0$(echo "${TEMPORADA}+0"|bc)"
	fi
	#Garante que se o usuario passar um numero sem zero a esquerda, ele sera colocado
	if [ ${EPISODIO} -lt 10 ]; then
		EPISODIO="0$(echo "${EPISODIO}+0"|bc)"
	fi
	
	PASTA_DESTINO="${PWD}/${SERIADO_ABREVIADO}_S${TEMPORADA}E${EPISODIO}"
	PASTA_TORRENT="${PASTA_DESTINO}/torrent"
	PASTA_LEGENDA="${PASTA_DESTINO}/legenda"
	PASTA_LOG="${PASTA_DESTINO}/logs"
	PASTA_TEMPORARIO="${PASTA_DESTINO}/temp"
	ARQUIVO_LOG="${PASTA_LOG}/download.log"

	#Cria a pasta onde tudo sera armazenado
	if [ ! -d "${PASTA_DESTINO}" ]; then
		mkdir ${PASTA_DESTINO}
	fi

	if [ ! -d "${PASTA_TORRENT}" ]; then
		mkdir ${PASTA_TORRENT}
	fi

	if [ ! -d "${PASTA_LEGENDA}" ]; then
		mkdir ${PASTA_LEGENDA}
	fi

	if [ ! -d "${PASTA_LOG}" ]; then
		mkdir ${PASTA_LOG}
	fi

	if [ ! -d "${PASTA_TEMPORARIO}" ]; then
		mkdir ${PASTA_TEMPORARIO}
	fi

	PADROES_TORRENT+=("720p;DIMENSION")
	PADROES_TORRENT+=("1080p;BATV;ettv")
	PADROES_TORRENT+=("720p;BATV")
	PADROES_TORRENT+=("1080p;BATV")
	PADROES_TORRENT+=("720p;TOPKEK")
	PADROES_TORRENT+=("1080p;TOPKEK")
	PADROES_TORRENT+=("720p;KILLERS")
	PADROES_TORRENT+=("1080p;KILLERS")
	PADROES_TORRENT+=("720p;IMMERSE")
	PADROES_TORRENT+=("1080p;IMMERSE")
	PADROES_TORRENT+=("HDTV;2HD;eztv")
	PADROES_TORRENT+=("720p;KILLERS;ettv")
	PADROES_TORRENT+=("KILLERS;ettv")
}

usage() {
    echo "uso: $0 [-s nome_do_seriado ] [-t numero_da_temporada] [-e numero_do_episodio] [-ln] [-lu usuarioLegendasTV -ls senhaLegendasTV] [-vn] [-h]"
	 echo "exemplo 1: $0 -s \"Game of Thrones\" -t 06 -e 09"
	 echo "exemplo 2: $0 -e 09"
	 echo "exemplo 3: $0 -s \"silicon valley\" -t 3 -e 1 -p \"x264;killers;ettv\""
	 echo ""
	 echo "-s | --seriado - Nome do seriado"
	 echo "-t | --temporada - Numero da temporada"
    echo "-e | --episodio - Numero do episodio"
	 echo "-ln | --semLegenda - Nao baixar legenda"
	 echo "-vn | --semVideo - Nao baixar video"
	 echo "-lu | --legendaUsuario - Usuário do LegendasTV"
	 echo "-ls | --legendaSenha - Senha do LegendasTV"
	 echo "-p | --padraoBusca - Adicionar padrao de busca para torrent"
	 echo "-h | --help - Ajuda"

}

#Funcoes para obter o hash de um arquivo - Ini
correct_64bit() {
	local pow32=$(( 1 << 32 ))

	while [ "$g_lo" -ge $pow32 ]; do
		g_lo=$(( g_lo - pow32 ))
		g_hi=$(( g_hi + 1 ))
	done
	while [ "$g_hi" -ge $pow32 ]; do
		g_hi=$(( g_hi - pow32 ))
	done
}


hash_part() {
	local file="$1"
	local curr=0
	local dsize=$((8192*8))

	local bytes_at_once=2048
	local groups=$(( (bytes_at_once / 8) - 1 ))
	local k=0
	local i=0
	local offset=0
	declare -a num=()

	while [ "$curr" -lt "$dsize" ]; do
		num=( $(od -t u1 -An -N "$bytes_at_once" -w$bytes_at_once -j "$curr" "$file") )

		for k in $(seq 0 $groups); do

			offset=$(( k * 8 ))

			g_lo=$(( g_lo + \
				num[$(( offset + 0 ))] + \
				(num[$(( offset + 1 ))] << 8) + \
				(num[$(( offset + 2 ))] << 16) + \
				(num[$(( offset + 3 ))] << 24) ))

			g_hi=$(( g_hi + \
				num[$(( offset + 4 ))] + \
				(num[$(( offset + 5 ))] << 8) + \
				(num[$(( offset + 6 ))] << 16) + \
				(num[$(( offset + 7 ))] << 24) ))

			correct_64bit
		done

		curr=$(( curr + bytes_at_once ))
	done
}


hash_file() {
	g_lo=0
	g_hi=0

	local file="$1"
	local size=$(stat -c%s "$file")
	local offset=$(( size - 65536 ))

	local part1=$(mktemp part1.XXXXXXXX)
	local part2=$(mktemp part2.XXXXXXXX)

	dd if="$file" bs=8192 count=8 of="$part1" 2> /dev/null
	dd if="$file" skip="$offset" bs=1 of="$part2" 2> /dev/null

	hash_part "$part1"
	hash_part "$part2"

	g_lo=$(( g_lo + size ))
	correct_64bit

	unlink "$part1"
	unlink "$part2"

	printf "%08x%08x\n" $g_hi $g_lo
}
#Funcoes para obter o hash de um arquivo - Fim

#Realiza a leitura dos parâmetros quando informados
while [ "$1" != "" ]; do
    case $1 in
        -s | --seriado )        shift
                                SERIADO=$1
										  SERIADO_ABREVIADO=$(echo $SERIADO | cut -c-3 | tr '[:lower:]' '[:upper:]')
                                ;;
		  -t | --temporada )      shift
                                TEMPORADA=$1
                                ;;
        -e | --episodio )    	  shift
										  EPISODIO=$1
										  ;;
		  -p | --padraoBusca )    shift
										  PADROES_TORRENT+=($1)
										  ;;
		  -ln | --semLegenda )	  BAIXAR_LEGENDA="NAO"
                                ;;
		  -vn | --semVideo )		  BAIXAR_VIDEO="NAO"
                                ;;
		  -lu | --legendaUsuario) shift
										  LEGENDASTV_USER=$1
										  ;;
		  -ls | --legendaSenha)   shift
										  LEGENDASTV_PASS=$1
										  ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage		
                                exit 1
    esac
    shift
done

iniciarTrabalhos

echo "Iniciando os trabalhos para encontrar ${SERIADO} S${TEMPORADA}E${EPISODIO}... Boa sorte ;)"

if [ $BAIXAR_VIDEO == "SIM" ]; then
	baixarEpisodio
fi

if [ $BAIXAR_LEGENDA == "SIM" ]; then
	#buscarLegenda_LegendasTV
	RET="false"
	while [ "$RET" == "false" ]
	do
		RET=$( buscarLegenda_OpenSubtitles )
		if [ "$RET" == "false" ]; then
     		echo "$(date) - Aguardando 15 minutos ate a proxima procura no OpenSubtitles" >> ${ARQUIVO_LOG}
			sleep 15m
		fi
	done
fi

echo "$(date) - Fim" >> ${ARQUIVO_LOG}