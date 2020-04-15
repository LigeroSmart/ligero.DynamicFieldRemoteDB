# --
# Kernel/Language/de_DynamicFieldRemoteDB.pm - provides german language translation for DynamicFieldRemoteDB package
# Copyright (C) 2006-2016 c.a.p.e. IT GmbH, http://www.cape-it.de
#
# written/changed by:
# * Mario(dot)Illinger(at)cape(dash)it(dot)de
# * Stefan(dot)Mehlig(at)cape(dash)it(dot)de
# * Anna(dot)Litvinova(at)cape(dash)it(dot)de
# --
# $Id: de_DynamicFieldRemoteDB.pm,v 1.13 2016/03/01 13:08:09 millinger Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
package Kernel::Language::pt_BR_DynamicFieldRemoteDB;
use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;
    my $Lang = $Self->{Translation};
    return 0 if ref $Lang ne 'HASH';

    # possible charsets
    $Self->{Charset} = ['utf-8', ];

    # $$START$$

    # Options
    $Lang->{'MaxArraySize'}  = 'Tamanho máximo da Lista';
    $Lang->{'ItemSeparator'} = 'Separador de Item';

    $Lang->{'DatabaseDSN'}         = 'DSN do Banco de Dados';
    $Lang->{'DatabaseUser'}        = 'Usuário do Banco de Dados';
    $Lang->{'DatabasePw'}          = 'Senha do Banco de Dados';
    $Lang->{'DatabaseTable'}       = 'Tabela do Banco de Dados';
    $Lang->{'DatabaseFieldKey'}    = 'Campo Chave da Tabela';
    $Lang->{'DatabaseFieldValue'}  = 'Campo Valor da Tabela';
    $Lang->{'DatabaseFieldSearch'} = 'Campo para usar na Busca';

    $Lang->{'SearchPrefix'} = 'Prefixo de Busca';
    $Lang->{'SearchSuffix'} = 'Sufixo de Busca';

    $Lang->{'CachePossibleValues'} = 'Cache de Valores Possíveis';

    $Lang->{'Constrictions'} = 'Constrições';

    $Lang->{'ShowKeyInTitle'}     = 'Mostrar Chave no Título';
    $Lang->{'ShowKeyInSearch'}    = 'Mostrar Chave na Busca';
    $Lang->{'ShowKeyInSelection'} = 'Mostrar Chave na Seleção';
    $Lang->{'ShowMatchInResult'}  = 'Mostrar Equivalência no Resultado';

    $Lang->{'EditorMode'} = 'Modo Editor';

    $Lang->{'MinQueryLength'} = 'Tamanho mínimo da Consulta';
    $Lang->{'QueryDelay'}     = 'Tempo de Espera';
    $Lang->{'MaxQueryResult'} = 'Resultado Máximo da Consulta';

    # Descriptions...
    $Lang->{'Specify the maximum number of entries.'}
        = 'Especifique o número máximo de entradas.';
    $Lang->{'Specify the DSN for used database.'}      = 'Especifique o DSN para o banco de dados usado.';
    $Lang->{'Specify the user for used database.'}     = 'Especifique o usuário para o banco de dados usado.';
    $Lang->{'Specify the password for used database.'} = 'Especifique a senha para o banco de dados usado.';
    $Lang->{'Specify the table for used database.'}    = 'Especifique a tabela para o banco de dados usado.';
    $Lang->{'Specify the field containing key in used database.'}
        = 'Especifique o campo que contém a chave no banco de dados usado.';
    $Lang->{'Uses DatabaseFieldKey if not specified.'}
        = 'Usa Chave da Tabela se não especificado.';
    $Lang->{'Specify the field containing value in used database.'}
        = 'Especifique o campo que contém valor no banco de dados usado.';
    $Lang->{'Specify Constrictions for search-queries. [TableColumn]::[Object]::[Attribute/Value]::[Mandatory]'}
        = 'Especifique Constrições para consultas de pesquisa. [TableColumn]::[Object]::[Attribute/Value]::[Obrigatório]';
    $Lang->{'Cache any database queries for time in seconds.'}
        = 'Coloque em cache qualquer consulta ao banco de dados por tempo em segundos.';
    $Lang->{'Cache all possible values.'} = 'Coloque em cache todos os valores possíveis.';
    $Lang->{'0 deactivates caching.'} = '0 desativa o cache.';
    $Lang->{'If active, the usage of values which recently added to the database may cause an error.'}
        = 'Se ativo, o uso de valores adicionados recentemente ao banco de dados pode causar um erro.';
    $Lang->{'Specify if key is added to HTML-attribute title.'}
        = 'Especifique se a chave foi adicionada ao título do atributo HTML.';
    $Lang->{'Specify if key is added to entries in search.'}
        = 'Especifique se a chave foi adicionada às entradas na pesquisa.';
    $Lang->{'Specify the separator of displayed values for this field.'}
        = 'Especifique o separador dos valores exibidos para este campo.';
    $Lang->{'for Agent'}                 = 'para Atendente';
    $Lang->{'Used in AgentFrontend.'}    = 'Usado no AgentFrontend.';
    $Lang->{'for Customer'}              = 'para Cliente';
    $Lang->{'Used in CustomerFrontend.'} = 'Usado no CustomerFrontend.';
    $Lang->{'Following placeholders can be used:'}
        = 'Os seguintes espaços reservados podem ser usados:';
    $Lang->{'Same placeholders as for agent link available.'}
        = 'Os mesmos espaços reservados para o link do agente disponível.';
    $Lang->{'Specify the field for search.'} = 'Especifique o campo para pesquisa.';
    $Lang->{'Multiple columns to search can be configured comma separated.'} = 'Várias colunas a serem pesquisadas podem ser configuradas separadas por vírgula.';
    $Lang->{'Specify a prefix for the search.'} = 'Especifique um prefixo para a pesquisa.';
    $Lang->{'Specify a suffix for the search.'} = 'Especifique um sufixo para a pesquisa.';
    $Lang->{'Specify the MinQueryLength. 0 deactivates the autocomplete.'}
        = 'Especifique o MinQueryLength. 0 desativa o preenchimento automático.';
    $Lang->{'Specify the QueryDelay.'} = 'Especifique o QueryDelay.';
    $Lang->{'Specify the MaxQueryResult.'}
        = 'Especifique o MaxQueryResult.';
    $Lang->{'Should the search be case sensitive?'} = 'A pesquisa deve diferenciar maiúsculas de minúsculas?';
    $Lang->{'Some database systems don\'t support this. (For example MySQL with default settings)'}
        = 'A pesquisa deve diferenciar maiúsculas de minúsculas? Alguns sistemas de banco de dados não suportam isso. (Por exemplo, MySQL com configurações padrão)';

    $Lang->{'Comma (,)'}      = 'Vírgula (,)';
    $Lang->{'Semicolon (;)'}  = 'Ponto e Vírgula (;)';
    $Lang->{'Whitespace ( )'} = 'Espaço em branco ( )';

    $Lang->{'Additional fields'} = 'Campos adicionais';
    $Lang->{'Dynamic Field'} = 'Campo Dinâmico';
    $Lang->{'Table Column'} = 'Coluna da Tabela';
    $Lang->{'Add field'} = 'Adicionar campo';

    $Lang->{'Use DISTINCT'} = 'Usar DISTINCT';
    $Lang->{'Use DISTINCT Clause in Query.'} = 'Usar a cláusula DISTINCT nas pesquisas.';

    $Lang->{'Just save description'} = 'Armazenar somente a descrição';
    $Lang->{'Just save the description value in OTRS.'} = 'Armazenar somente a descrição no OTRS.';

    $Lang->{'Additional Fields as Read Only'} = 'Campos adicionais como somente leitura';
    $Lang->{'Define all additional as ready only.'} = 'Define todos os campos adicionais como somente leitura.';

    return 0;

    # $$STOP$$
}
1;
