#!/bin/bash
#
# Copyright 2017 Sandro Marcell <smarcell@mail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
PATH='/bin:/sbin:/usr/bin:/usr/sbin'
LC_ALL='pt_BR.UTF-8'

# Diretorio onde serao armazenadas as bases de dados do rrdtool
BASES_RRD='/var/lib/rrd/rtt-graph'

# Diretorio no servidor web onde serao armazenados os arquivos html/png gerados
DIR_WWW='/var/www/html/rtt-graph'

# Gerar os graficos para os seguintes periodos de tempo
PERIODOS='day week month'

# Intervalo de atualizacao das paginas html (padrao 5 minutos)
INTERVALO=$((60 * 5))

# Vetor com as definicoes dos equipamentos e seus respectivos ip's
# !! ATENCAO: ao adicionar novas entradas, sempre MANTENHA a correta ordem 
# e sequencia dos indices deste vetor. !!
declare -a HOSTS

# Modem ADSL
HOSTS[0]='Modem ADSL - Zyxel'
HOSTS[1]='192.168.0.1'
# Roteador Intelbras
HOSTS[2]='Roteador Wireless - Intelbras'
HOSTS[3]='192.168.1.1'
# Roteador TPLINK
HOSTS[4]='Roteador Wireless - TPLINK'
HOSTS[5]='192.168.2.1'

# Criando os diretorios de trabalho caso nao existam
[ ! -d "$BASES_RRD" ] && { mkdir -p "$BASES_RRD" || exit 1; }
[ ! -d "$DIR_WWW" ] && { mkdir -p "$DIR_WWW" || exit 1; }

function gerarGraficos {
	declare -a args=("${HOSTS[@]}")
	declare -a latencia
	declare host=''
	declare ip=''
	declare retorno_ping=0
	declare pp=0
	declare rtt_min=0
	declare rtt_med=0
	declare rtt_max=0

	while [ ${#args[@]} -ne 0 ]; do
		host="${args[0]}" # Nome do equipamento
		ip="${args[1]}" # IP do equipamento
		args=("${args[@]:2}") # Descartando os dois elementos ja lidos anteriormente do vetor

		retorno_ping=$(ping -Q 16 -n -U -i 0.2 -c 10 -W 1 -q $ip)
		pp=$(echo $retorno_ping | grep -oP '\d+(?=% packet loss)') # Pacotes perdidos

		# Pingou ou nao pingou?! ^_^
		if [ $? -ne 0 ]; then
			latencia=(0 0 0)
		else
			latencia=($(echo $retorno_ping | awk -F '/' 'END { print $4,$5,$6 }' | grep -oP '\d.+'))
		fi

		# Latencias minimas, medias e maximas
		rtt_min="${latencia[0]}"
		rtt_med="${latencia[1]}"
		rtt_max="${latencia[2]}"

		# Caso as bases rrd nao existam, entao serao criadas e cada uma
		# tera o mesmo nome do ip verificado
		if [ ! -e "${BASES_RRD}/${ip}.rrd" ]; then
			# Armazenar valores de acordo com os peridos definidos em $PERIODO
			# e computados com base no intervalo de $INTERVALO
			v30min=$((INTERVALO * 2 / 30))  # Semanal
			v2hrs=$((INTERVALO * 2 / 120))  # Mensal
			v1d=$((1440 / (INTERVALO * 2))) # Anual
			
			echo "Criando base de dados rrd: ${BASES_RRD}/${ip}.rrd"
			rrdtool create ${BASES_RRD}/${ip}.rrd --start 0 --step $INTERVALO \
				DS:min:GAUGE:$((INTERVALO * 2)):0:U \
				DS:med:GAUGE:$((INTERVALO * 2)):0:U \
				DS:max:GAUGE:$((INTERVALO * 2)):0:U \
				DS:pp:GAUGE:$((INTERVALO * 2)):0:U \
				RRA:MIN:0.5:1:1500 \
				RRA:MIN:0.5:$v30min:1500 \
				RRA:MIN:0.5:$v2hrs:1500 \
				RRA:MIN:0.5:$v1d:1500 \
				RRA:AVERAGE:0.5:1:1500 \
				RRA:AVERAGE:0.5:$v30min:1500 \
				RRA:AVERAGE:0.5:$v2hrs:1500 \
				RRA:AVERAGE:0.5:$v1d:1500 \
				RRA:MAX:0.5:1:1500 \
				RRA:MAX:0.5:$v30min:1500 \
				RRA:MAX:0.5:$v2hrs:1500 \
				RRA:MAX:0.5:$v1d:1500
			[ $? -gt 0 ] && return 1
		fi

		# Se as bases ja existirem, entao atualize-as...
		echo "Atualizando base de dados: ${BASES_RRD}/${ip}.rrd"
		rrdtool update ${BASES_RRD}/${ip}.rrd --template pp:min:med:max N:${pp}:${rtt_min}:${rtt_med}:$rtt_max
		[ $? -gt 0 ] && return 1

		# e depois gere os graficos de acordo com os periodos
		for i in $PERIODOS; do
			case $i in
				  'day') tipo='Média diária (5 minutos)' ;;
				 'week') tipo='Média semanal (30 minutos)' ;;
				'month') tipo='Média mensal (2 horas)' ;;
			esac

			rrdtool graph ${DIR_WWW}/${ip}-${i}.png --start -1$i --lazy --font='TITLE:0:Bold' --title="$tipo" \
				--watermark="$(date "+%c")" --vertical-label='Latência (ms)' --height=124 --width=550 \
				--lower-limit=0 --units-exponent=0 --slope-mode --imgformat=PNG --alt-y-grid --rigid \
				--color='BACK#F8F8FF' --color='SHADEA#FFFFFF' --color='SHADEB#FFFFFF' \
				--color='MGRID#AAAAAA' --color='GRID#CCCCCC' --color='ARROW#333333' \
				--color='FONT#333333' --color='AXIS#333333' --color='FRAME#333333' \
				DEF:rtt_min=${BASES_RRD}/${ip}.rrd:min:MIN \
				DEF:rtt_med=${BASES_RRD}/${ip}.rrd:med:AVERAGE \
				DEF:rtt_max=${BASES_RRD}/${ip}.rrd:max:MAX \
				DEF:rtt_pp=${BASES_RRD}/${ip}.rrd:pp:AVERAGE \
				VDEF:vpp=rtt_pp,100,PERCENT \
				VDEF:vmin=rtt_min,MINIMUM \
				VDEF:vmed=rtt_med,AVERAGE \
				VDEF:vmax=rtt_max,MAXIMUM \
				"COMMENT:$(printf '%5s')" \
				"LINE1:rtt_min#009900:Miníma\:$(printf '%11s')" \
				GPRINT:vmin:"%1.3lfms\l" \
				"COMMENT:$(printf '%5s')" \
				"LINE1:rtt_max#990000:Máxima\:$(printf '%11s')" \
				GPRINT:vmax:"%1.3lfms\l" \
				"COMMENT:$(printf '%5s')" \
				"LINE1:rtt_med#0066CC:Média\:$(printf '%12s')" \
				GPRINT:vmed:"%1.3lfms\l" \
				"COMMENT:$(printf '%5s')" \
				"HRULE:vpp#000000:Pacotes perdidos\:$(printf '%1s')" \
				GPRINT:vpp:"%1.0lf%%\l" 1> /dev/null
			[ $? -gt 0 ] && return 1
		done
	done
	return 0
}

function criarPaginasHTML {
	declare -a args=("${HOSTS[@]}")
	declare -a ips
	declare host=''
	declare ip=''
	declare titulo='GR&Aacute;FICOS ESTAT&Iacute;STICOS DE LAT&Ecirc;NCIA DE REDE'
	
	# Filtrando o vetor $HOSTS para retornar somente os ips
	for ((i = 0; i <= ${#HOSTS[@]}; i++)); do
		((i % 2 == 1)) && ips+=("${HOSTS[$i]}")
	done
	
	echo 'Criando paginas HTML...'
	
	# 1o: Criar a pagina index
	cat <<- FIM > ${DIR_WWW}/index.html
		<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
		"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
		<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
		<head>
		<title>${0##*/}</title>
		<meta http-equiv="content-type" content="text/html;charset=utf-8" />
		<meta name="generator" content="Geany 1.24.1" />
		<meta name="author" content="Sandro Marcell" />
		<style type="text/css">
			* { box-sizing: border-box; }
			html, body { margin:0; padding:0; background:#DDD; color:#333; font: 14px/1.5em Helvetica, Arial, sans-serif; }
			a { text-decoration: none; color: #C33; }
			header, footer, article, nav, section { float: left; padding: 10px; }
			header,footer { width:100%; }
			header, footer { background-color: #333; color: #FFF; text-align: right; height: 100px; }
			header { font-size: 1.8em; font-weight: bold; }
			footer{ background-color: #999; text-align: center; height: 40px; }
			nav { text-align: center; width: 24%; margin-right: 1%; border: 1px solid #CCC; margin:5px; margin-top: 10px; }
			nav a { display: block; width: 100%; background-color: #C33; color: #FFF; height: 30px; margin-bottom: 10px; padding: 10px; border-radius: 3px; line-height: 10px; vertical-align: middle; }
			nav a:hover, nav a:active { background-color: #226; }
			article { width: 75%; height: 1000px; }
			h1 { padding: 0; margin: 0 0 20px 0; text-align: center; }
			p { text-align: center; margin-top: 30px; }
			article section { padding: 0; width: 100%; height: 100%; }
			.container{ width: 1200px; float: left; position: relative; left: 50%; margin-left: -600px; background:#FFF; padding: 10px; }
			.conteudo { width: 100%; height: 100%; overflow: hidden;}
			.oculto { display: none; }
		</style>
		<script type="text/javascript">
			function exibirGraficos(id) {
				document.getElementById('objetos').innerHTML = document.getElementById(id).innerHTML;
			}
		</script>
		</head>
		<body>
		<div class="container">
			<nav>
				$(while [ ${#args[@]} -ne 0 ]; do
					host="${args[0]}"
					ip="${args[1]}"
					args=("${args[@]:2}")
					echo "<a href="\"javascript:exibirGraficos\("'$ip'"\)\;\"">$host</a>"
				done)
			</nav>
			<article>
				<h1>GR&Aacute;FICOS ESTAT&Iacute;STICOS DE LAT&Ecirc;NCIA DE REDE</h1>
				<div id="objetos" class="conteudo"><p>* Clique para visualizar os gr&aacute;ficos.</p></div>
				<section>
					$(for i in "${ips[@]}"; do
						echo "<div id="\"$i\"" class="\"oculto\""><object type="\"text/html\"" data="\"${i}.html\"" class="\"conteudo\""></object></div>"
					done)
				</section>
			</article>
			<footer>
				<small>${0##*/} &copy; 2017 Sandro Marcell</small>
			</footer>
		</div>
	</body>   
	</html>	
	FIM

	# 2o: Criar pagina especifica para cada host com os periodos definidos
	while [ ${#HOSTS[@]} -ne 0 ]; do
		host="${HOSTS[0]}"
		ip="${HOSTS[1]}"
		HOSTS=("${HOSTS[@]:2}")

		cat <<- FIM > ${DIR_WWW}/${ip}.html
		<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
		"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
		<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
		<head>
		<title>${0##*/}</title>
		<meta http-equiv="content-type" content="text/html;charset=utf-8" />
		<meta http-equiv="refresh" content="$INTERVALO" />
		<meta name="author" content="Sandro Marcell" />
		<style type="text/css">
		body { margin: 0; padding: 0; background-color: #FFFFFF; width: 100%; height: 100%; font: 20px/1.5em Helvetica, Arial, sans-serif; }
		#header { text-align: center; }
		#content { position: relative; text-align: center; margin: auto; }
		#footer { font-size: 13px; text-align: center; }
		</style>
		</head>
		<body>
			<div id="header">
				<p>$host<br /><small>($ip)</small></p>
			</div>
			<div id="content">
				<script type="text/javascript">
					$(for i in $PERIODOS; do
						echo "document.write('<div><img src="\"${ip}-${i}.png?nocache=\' + Math.random\(\) + \'\"" alt="\"${0##*/} --html\"" /></div>');"
					done)
				</script>
			</div>
		</body>
		</html>
		FIM
	done
	return 0
}

# Criar os arquivos html se for o caso
# Chamada do script: rtt-graph.sh --html
if [ "$1" == '--html' ]; then
	criarPaginasHTML
	exit 0
fi

# Coletando dados e gerando os graficos
# Chamada do script: rtt-graph.sh
gerarGraficos
