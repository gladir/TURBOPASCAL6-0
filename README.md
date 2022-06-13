# TURBOPASCAL6-0
Clone des commandes du Turbo Pascal 6

<h2>Liste des fichiers</h2>

Voici la liste des différents fichiers proposés dans TURBOPASCAL6-0 :

<table>
		<tr>
			<th>Nom</th>
			<th>Description</th>	
		</tr>
   <tr>
			 <td><b>CPUTEST.PAS</b></td>
			 <td>Cette commande permet de détecter le type de microprocesseur. Cette commande est un clone de la commande CPUTEST du Turbo Pascal 6.</td>
		</tr>
    <tr>
			 <td><b>EMSTEST.PAS</b></td>
			 <td>Cette commande permet de tester la mémoire EMS. Cette commande est un clone de la commande EMSTEST du Turbo Pascal 6.</td>
		</tr>	
		<tr>
			<td><b>GREP.PAS</b></td>
			<td>Cette commande permet d'effectuer des recherches dans des fichiers. Cette commande est un équivalent de UNIX.</td>
		</tr>
    <tr>
		   <td><b>GREP2MSG.PAS</b></td>
			<td>Cette programme permet de capturer les messages GREP et de les retourner a Turbo Pascal.</td>
		</tr>
     <tr>
			<td><b>TOUCH.PAS</b></td>
			<td>Cette commande permet de changer la date et l'heure d'un fichier. Cette commande est un équivalent de UNIX, AIX et Linux.</td>
	   </tr>
</table>

<h2>Compilation</h2>
	
Les fichiers Pascal n'ont aucune dépendances, il suffit de télécharger le fichier désiré et de le compiler avec Free Pascal avec la syntaxe de commande  :

<pre><b>fpc</b> <i>LEFICHIER.PAS</i></pre>
	
Sinon, vous pouvez également le compiler avec le Turbo Pascal à l'aide de la syntaxe de commande suivante :	

<pre><b>tpc</b> <i>LEFICHIER.PAS</i></pre>
	
Par exemple, si vous voulez compiler GREP.PAS, vous devrez tapez la commande suivante :

<pre><b>fpc</b> GREP.PAS</pre>

<h2>Licence</h2>
<ul>
 <li>Le code source est publié sous la licence <a href="https://github.com/gladir/TURBOPASCAL6-0/blob/main/LICENSE">MIT</a>.</li>
 <li>Le paquet original est publié sous la licence <a href="https://github.com/gladir/TURBOPASCAL6-0/blob/main/LICENSE">MIT</a>.</li>
</ul>
