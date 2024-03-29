
package Kernel::System::DynamicField::Driver::RemoteDB;

use strict;
use warnings;

use base qw(Kernel::System::DynamicField::Driver::Base);

use Kernel::System::DFRemoteDB;
use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::Log',
    'Kernel::System::Main',
);

=head1 NAME

Kernel::System::DynamicField::Driver::RemoteDB

=head1 SYNOPSIS

DynamicFields RemoteDB backend delegate

=head1 PUBLIC INTERFACE

This module implements the public interface of L<Kernel::System::DynamicField::Backend>.
Please look there for a detailed reference of the functions.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # create additional objects
    $Self->{ConfigObject}            = $Kernel::OM->Get('Kernel::Config');
    $Self->{DBObject}                = $Kernel::OM->Get('Kernel::System::DB');
    $Self->{DynamicFieldValueObject} = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');
    $Self->{LogObject}               = $Kernel::OM->Get('Kernel::System::Log');

    # get the fields config
    $Self->{FieldTypeConfig} = $Self->{ConfigObject}->Get('DynamicFields::Driver') || {};

    # set field behaviors
    $Self->{Behaviors} = {
        'IsACLReducible'               => 0,
        'IsNotificationEventCondition' => 1,
        'IsSortable'                   => 1,
        'IsFiltrable'                  => 1,
        'IsStatsCondition'             => 1,
        'IsCustomerInterfaceCapable'   => 1,
    };

    # get the Dynamic Field Backend custom extensions
    my $DynamicFieldDriverExtensions = $Kernel::OM->Get('Kernel::Config')->Get('DynamicFields::Extension::Driver::RemoteDB');

    EXTENSION:
    for my $ExtensionKey ( sort keys %{$DynamicFieldDriverExtensions} ) {

        # skip invalid extensions
        next EXTENSION if !IsHashRefWithData( $DynamicFieldDriverExtensions->{$ExtensionKey} );

        # create a extension config shortcut
        my $Extension = $DynamicFieldDriverExtensions->{$ExtensionKey};

        # check if extension has a new module
        if ( $Extension->{Module} ) {

            # check if module can be loaded
            if (
                !$Kernel::OM->Get('Kernel::System::Main')->RequireBaseClass( $Extension->{Module} )
                )
            {
                die "Can't load dynamic fields backend module"
                    . " $Extension->{Module}! $@";
            }
        }

        # check if extension contains more behaviors
        if ( IsHashRefWithData( $Extension->{Behaviors} ) ) {

            %{ $Self->{Behaviors} } = (
                %{ $Self->{Behaviors} },
                %{ $Extension->{Behaviors} }
            );
        }
    }

    return $Self;
}

sub ValueGet {
    my ( $Self, %Param ) = @_;

    my $DFValue = $Self->{DynamicFieldValueObject}->ValueGet(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
    );

    return if !$DFValue;
    return if !IsArrayRefWithData($DFValue);
    return if !IsHashRefWithData( $DFValue->[0] );

    # extract real values
    my @ReturnData;
    for my $Item ( @{$DFValue} ) {
        push @ReturnData, $Item->{ValueText}
    }

    return \@ReturnData;
}

sub ValueSet {
    my ( $Self, %Param ) = @_;

    # check value
    my @Values;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }

    my $Success;
    if ( IsArrayRefWithData( \@Values ) ) {

        # if there is at least one value to set, this means one or more values are selected,
        #    set those values!
        my @ValueText;
        for my $Item (@Values) {
            push @ValueText, { ValueText => $Item };
        }

        $Success = $Self->{DynamicFieldValueObject}->ValueSet(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            Value    => \@ValueText,
            UserID   => $Param{UserID},
        );
    }
    else {

        # otherwise no value was selected, then in fact this means that any value there should be
        # deleted
        $Success = $Self->{DynamicFieldValueObject}->ValueDelete(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            UserID   => $Param{UserID},
        );
    }

    return $Success;
}

sub ValueLookup {
    my ( $Self, %Param ) = @_;

    return if (!defined ($Param{Key}));
    return '' if ($Param{Key} eq '');

    my $DFRemoteDBObject;

    if ( $Param{DynamicFieldConfig}->{Config}->{UseOTRSDB} ) {
        $DFRemoteDBObject = $Kernel::OM->Get('Kernel::System::DB');
    }
    else {
        $DFRemoteDBObject = Kernel::System::DFRemoteDB->new(
            DatabaseDSN  => $Param{DynamicFieldConfig}->{Config}->{DatabaseDSN},
            DatabaseUser => $Param{DynamicFieldConfig}->{Config}->{DatabaseUser},
            DatabasePw   => $Param{DynamicFieldConfig}->{Config}->{DatabasePw},
            %{ $Self },
        );
    }

    # return array or scalar depending on $Param{Key}
    my $Result;
    my @Keys;
    if ( ref $Param{Key} eq 'ARRAY' ) {
        @Keys = @{$Param{Key}};
        $Result = [];
    }
    else{
        push(@Keys, $Param{Key});
        $Result = '';
    }

    for my $Key ( @Keys ){

        my $QuotedValue = $DFRemoteDBObject->Quote($Key);

        if( $Param{DynamicFieldConfig}->{Config}->{SaveDescription} ){
            return $QuotedValue;
        }

        # check if value is in cache
        if ( $Param{DynamicFieldConfig}->{Config}->{CacheTTL} ) {
            $Self->{CacheType} = 'DynamicField_RemoteDB_' . $Param{DynamicFieldConfig}->{Name};

            my $Value = $Kernel::OM->Get('Kernel::System::Cache')->Get(
                Type => $Self->{CacheType},
                Key  => "ValueLookup::$QuotedValue",
            );
            if ( $Value &&  ref $Param{Key} eq 'ARRAY' ) {
                push(@{$Result}, $Value);
                next;
            }
            else{
                return $Value if $Value;
            }
        }

        my $QueryCondition = " WHERE";
        if ( length($QuotedValue) ) {
            $QueryCondition .= $DFRemoteDBObject->QueryCondition(
                Key           => $Param{DynamicFieldConfig}->{Config}->{DatabaseFieldKey},
                Value         => $QuotedValue,
                CaseSensitive => 1,
            );
        }
        else {
            $QueryCondition = "";
        }

        my $Distinct = "";
        if($Param{DynamicFieldConfig}->{Config}->{UseDESTINCT}){
            $Distinct = " DISTINCT ";
        }

        my $SQL = 'SELECT '
            . $Param{DynamicFieldConfig}->{Config}->{DatabaseFieldValue}
            . $Distinct
            . ' FROM '
            . $Param{DynamicFieldConfig}->{Config}->{DatabaseTable}
            . $QueryCondition;

        my $Success = $DFRemoteDBObject->Prepare(
            SQL   => $SQL,
            Limit => 1,
        );
        if ( !$Success ) {
            return;
        }

        my $Value;
        while (my @Row = $DFRemoteDBObject->FetchrowArray()) {
            $Value = $Row[0];
            last;
        }

        $Value = defined $Value ? $Value : $Param{Key};

        if ( ref $Result eq 'ARRAY' ) {
            push(@{$Result}, $Value);
        }
        else{
            $Result = $Value;
        }

        # cache request
        if ( $Param{DynamicFieldConfig}->{Config}->{CacheTTL} ) {
            $Kernel::OM->Get('Kernel::System::Cache')->Set(
                Type  => $Self->{CacheType},
                Key   => "ValueLookup::$QuotedValue",
                Value => $Value,
                TTL   => $Param{DynamicFieldConfig}->{Config}->{CacheTTL},
            );
        }
    }

    return $Result;
}

sub ValueIsDifferent {
    my ( $Self, %Param ) = @_;

    # special cases where the values are different but they should be reported as equals
    if (
        !defined $Param{Value1}
        && ref $Param{Value2} eq 'ARRAY'
        && !IsArrayRefWithData( $Param{Value2} )
        )
    {
        return
    }
    if (
        !defined $Param{Value2}
        && ref $Param{Value1} eq 'ARRAY'
        && !IsArrayRefWithData( $Param{Value1} )
        )
    {
        return
    }

    # compare the results
    return DataIsDifferent(
        Data1 => \$Param{Value1},
        Data2 => \$Param{Value2}
    );
}

sub ValueValidate {
    my ( $Self, %Param ) = @_;

    # check value
    my @Values;
    if ( IsArrayRefWithData( $Param{Value} ) ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }

    my $Success;
    for my $Item (@Values) {

        $Success = $Self->{DynamicFieldValueObject}->ValueValidate(
            Value => {
                ValueText => $Item,
            },
            UserID => $Param{UserID}
        );

        return if !$Success
    }

    return $Success;
}

sub PossibleValuesGet {
    my ( $Self, %Param ) = @_;

    # to store the possible values
    my $PossibleValues = $Self->_GetPossibleValues(%Param);

    # return the possible values hash as a reference
    return $PossibleValues;
}

sub TemplateValueTypeGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # set the field types
    my $EditValueType   = 'ARRAY';
    my $SearchValueType = 'ARRAY';

    # return the correct structure
    if ( $Param{FieldType} eq 'Edit' ) {
        return {
            $FieldName => $EditValueType,
        }
    }
    elsif ( $Param{FieldType} eq 'Search' ) {
        return {
            'Search_' . $FieldName => $SearchValueType,
        }
    }
    else {
        return {
            $FieldName             => $EditValueType,
            'Search_' . $FieldName => $SearchValueType,
        }
    }
}

sub EditFieldRender {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldID     = $Param{DynamicFieldConfig}->{ID};
    my $FieldName   = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    my $Value;

    # set the field value or default
    if ( $Param{UseDefaultValue} ) {
        $Value = ( defined $FieldConfig->{DefaultValues} ? $FieldConfig->{DefaultValues} : '' );
    }
    $Value = $Param{Value} // $Value;

    # check if a value in a template (GenericAgent etc.)
    # is configured for this dynamic field
    if (
        IsHashRefWithData( $Param{Template} )
        && defined $Param{Template}->{$FieldName}
        )
    {
        $Value = $Param{Template}->{$FieldName};
    }

    # extract the dynamic field value form the web request
    my $FieldValue = $Self->EditFieldValueGet(
        %Param,
    );

    # set values from ParamObject if present
    if ( IsArrayRefWithData($FieldValue) ) {
        $Value = $FieldValue;
    }

    # check and set class if necessary
    my $FieldClass = '';
    if ( defined $Param{Class} && $Param{Class} ne '' ) {
        $FieldClass = $Param{Class};
    }

    # set field as mandatory
    if ( $Param{Mandatory} ) {
        $FieldClass .= ' Validate_Required';
    }

    # set error css class
    if ( $Param{ServerError} ) {
        $FieldClass .= ' ServerError';
    }

    # check value
    my $SelectedValuesArrayRef = [];
    if ( defined $Value ) {
        if ( ref $Value eq 'ARRAY' ) {
            $SelectedValuesArrayRef = $Value;
        }
        else {
            $SelectedValuesArrayRef = [$Value];
        }
    }

    my $AutoCompleteFieldName = $FieldName . "_AutoComplete";
    my $ContainerFieldName    = $FieldName . "_Container";
    my $DisplayFieldName      = $FieldName . "_Display";
    my $IDCounterName         = $FieldName . "_IDCount";
    my $ValidateFieldName     = $FieldName . "_Validate";
    my $ValueFieldName        = $FieldName . "_";

    my $MaxArraySize          = $FieldConfig->{MaxArraySize} || 1;

    my $TranslateRemoveSelection = $Param{LayoutObject}->{LanguageObject}->Translate("Remove selection");

    my $HTMLString = <<"END";
    <input id="$FieldName" type="text" style="display:none;" />
    <div class="InputField_Container W50pc">
        <input id="$AutoCompleteFieldName" type="text" style="margin-bottom:2px;" />
        <span id="AJAXLoader$AutoCompleteFieldName" class="AJAXLoader" style="display: none;"></span>
        <div class="Clear"></div>
        <div id="$ContainerFieldName" class="InputField_InputContainer" style="display:block;">
END

    my $ValueCounter = 0;
    my $ScriptItems = "";
    for my $Key ( @{ $SelectedValuesArrayRef } ) {
        next if (!$Key);
        $ValueCounter++;

        my $Label = $Self->ValueLookup(
            %Param,
            Key => $Key,
        );

        my $Title = $Label;
        if ( $Param{DynamicFieldConfig}->{Config}->{ShowKeyInTitle} ) {
            $Title .= ' (' . $Key . ')';
        }

        $HTMLString .= <<"END";
        <div class="InputField_Selection" style="display:block;position:inherit;top:0px;">
            <input id="$ValueFieldName$ValueCounter" type="hidden" name="$FieldName" value="$Key" />
            <div class="Text" title="$Title">$Label</div><div class="Remove"><a href="#" role="button" title="$TranslateRemoveSelection" tabindex="-1" aria-label="$TranslateRemoveSelection: $Label">x</a></div>
            <div class="Clear"></div>
        </div>
END


my $ClearAdditional1 = "";
        if($Param{DynamicFieldConfig}->{Config}->{PossibleValues}){
            foreach my $key (sort keys %{$Param{DynamicFieldConfig}->{Config}->{PossibleValues}}) {
                $ClearAdditional1 .= <<"END";
        \$('#DynamicField_$key').val('');
END
            }
        }
    

        $ScriptItems.= <<"END";
            
            \$('#$ValueFieldName$ValueCounter').siblings('div.Remove').find('a').bind('click', function() {
                $ClearAdditional1
                \$('#$ValueFieldName$ValueCounter').parent().remove();
                if (\$('.InputField_Selection > input[name=$FieldName]').length == 0) {
                    \$('#$ContainerFieldName').hide().append(
                        '<input class="InputField_Dummy" type="hidden" name="$FieldName" value="" />'
                    );
                }
                if (\$('.InputField_Selection > input[name=$FieldName]').length < $MaxArraySize) {
                    \$('#$AutoCompleteFieldName').show();
                }
                \$('#$FieldName').trigger('change');
                return false;
            });
END
    }

    my $ValidValue = "";
    if($ValueCounter){
       $ValidValue = '1';
    }

    $HTMLString .= <<"END";
        </div>
        <input id="$ValidateFieldName" type="text" class="$FieldClass" value="$ValidValue" style="display:none;" />
        <div class="Clear"></div>
    </div>
END

    if($Param{DynamicFieldConfig}->{Config}->{AdditionalFieldRO}){
        if($Param{DynamicFieldConfig}->{Config}->{PossibleValues}){
            foreach my $key (sort keys %{$Param{DynamicFieldConfig}->{Config}->{PossibleValues}}) {
                $ScriptItems.= <<"END";
                \$('#DynamicField_$key').attr('readonly', true);
END
            }
        }
    }

my $ClearAdditional = "";
        if($Param{DynamicFieldConfig}->{Config}->{PossibleValues}){
            foreach my $key (sort keys %{$Param{DynamicFieldConfig}->{Config}->{PossibleValues}}) {
                $ClearAdditional .= <<"END";
        \$('#DynamicField_$key').val('');
END
            }
        }
    $HTMLString .= <<"END";
        <script>
            function initScript$AutoCompleteFieldName(){
                $ScriptItems
    var $IDCounterName = $ValueCounter;
    \$('#$AutoCompleteFieldName').autocomplete({
        delay: $FieldConfig->{QueryDelay},
        minLength: $FieldConfig->{MinQueryLength},
        source: function (Request, Response) {
            var Data = {};
            Data.Action         = 'DynamicFieldRemoteDBAJAXHandler';
            Data.Subaction      = 'Search';
            Data.Search         = Request.term;
            Data.DynamicFieldID = $FieldID;

            var additionalFilter = '$Param{DynamicFieldConfig}->{Config}->{AdditionalFilters}';

            if(additionalFilter !== ""){

                var addFilterList = additionalFilter.split(",");

                Data.AdditionalFilters = "";

                for(var item of addFilterList){
                    var columnName = item.split("=")[0];
                    var fieldName = item.split("=")[1];
                    var fieldValue = \$('[name ="'+fieldName+'"]').val();
                    Data.AdditionalFilters += " AND "+columnName+"='"+fieldValue+"'";
                }
            }

            var QueryString = Core.AJAX.SerializeForm(\$('#$AutoCompleteFieldName'), Data);
            \$.each(Data, function (Key, Value) {
                QueryString += ';' + encodeURIComponent(Key) + '=' + encodeURIComponent(Value);
            });

            if (\$('#$AutoCompleteFieldName').data('AutoCompleteXHR')) {
                \$('#$AutoCompleteFieldName').data('AutoCompleteXHR').abort();
                \$('#$AutoCompleteFieldName').removeData('AutoCompleteXHR');
            }
            \$('#AJAXLoader$AutoCompleteFieldName').show();
            \$('#$AutoCompleteFieldName').data('AutoCompleteXHR', Core.AJAX.FunctionCall(Core.Config.Get('CGIHandle'), QueryString, function (Result) {
                var Data = [];
                \$.each(Result, function () {
                    Data.push({
                        key:   this.Key,
                        value: this.Value,
                        title: this.Title,
                        aditionalFields: this.AditionalField,
                        saveDescription: this.SaveDescription
                    });
                });
                \$('#$AutoCompleteFieldName').data('AutoCompleteData', Data);
                \$('#$AutoCompleteFieldName').removeData('AutoCompleteXHR');
                \$('#AJAXLoader$AutoCompleteFieldName').hide();
                Response(Data);
            }).fail(function() {
                \$('#AJAXLoader$AutoCompleteFieldName').hide();
                Response(\$('#$AutoCompleteFieldName').data('AutoCompleteData'));
            }));
        },
        select: function (Event, UI) {
            if(UI.item.aditionalFields.length > 0){
                for (let field of UI.item.aditionalFields) {
                    \$('#'+field.field).val(field.value);
                }
            }
            $IDCounterName++;
            \$('#$ContainerFieldName').append(
                '<div class="InputField_Selection" style="display:block;position:inherit;top:0px;">'
                + '<input id="$ValueFieldName'
                + $IDCounterName
                + '" type="hidden" name="$FieldName" value="'
                + UI.item.key
                + '" />'
                + '<div class="Text" title="'
                + UI.item.title
                + '">'
                + UI.item.value
                + '</div>'
                + '<div class="Remove"><a href="#" role="button" title="$TranslateRemoveSelection" tabindex="-1" aria-label="$TranslateRemoveSelection: '
                + UI.item.value
                + '">x</a></div><div class="Clear"></div>'
                + '</div>'
            );
            \$("#$ValueFieldName"+"Validate").attr("value",UI.item.key);
            \$('#$ValueFieldName' + $IDCounterName).siblings('div.Remove').find('a').data('counter', $IDCounterName);
            \$('#$ValueFieldName' + $IDCounterName).siblings('div.Remove').find('a').bind('click', function() {
                $ClearAdditional
                \$('#$ValueFieldName' + \$(this).data('counter')).parent().remove();
                if (\$('.InputField_Selection > input[name=$FieldName]').length == 0) {
                    \$('#$ContainerFieldName').hide().append(
                        '<input class="InputField_Dummy" type="hidden" name="$FieldName" value="" />'
                    );
                }
                if (\$('.InputField_Selection > input[name=$FieldName]').length < $MaxArraySize) {
                    \$('#$AutoCompleteFieldName').show();
                }
                if(UI.item.saveDescription == 0)
                    \$('#$FieldName').trigger('change');
                return false;
            });
            \$('#$ContainerFieldName').show();
            \$('#$ContainerFieldName > .InputField_Dummy').remove();
            \$('#$AutoCompleteFieldName').val('');
            if (\$('.InputField_Selection > input[name=$FieldName]').length >= $MaxArraySize) {
                \$('#$AutoCompleteFieldName').hide();
            }
            if(UI.item.saveDescription == 0)
                \$('#$FieldName').trigger('change');
            Event.preventDefault();
            for (let field of UI.item.aditionalFields) {
                 \$('#'+field.field).trigger('change');
            }
            return false;
        },
    });
    \$('#$AutoCompleteFieldName').blur(function() {
        \$(this).val('');
        if ( \$('#$ValidateFieldName').hasClass('Error') ) {
            \$('label[for=$FieldName]').addClass('LabelError');
            \$('#$AutoCompleteFieldName').addClass('Error');
        } else {
            \$('label[for=$FieldName]').removeClass('LabelError');
            \$('#$AutoCompleteFieldName').removeClass('Error');
        }
    });
    \$('#$FieldName').change(function() {
        if (\$('#$FieldName').data('AJAXRequest')) {
            \$('#$FieldName').data('AJAXRequest').abort();
            \$('#$FieldName').removeData('AJAXRequest');
        }

        \$('#$ValidateFieldName').val('');
        \$('.InputField_Selection > input[name=$FieldName]').each(function () {
            if(\$(this).val()){
                \$('#$ValidateFieldName').removeClass('Error');
                \$('#$ValidateFieldName').val('1');
                return false;
            }
        });

        if (\$('#$FieldName').val().length == 0) {
            return false;
        }

        var Data = {};
        Data.Action         = 'DynamicFieldRemoteDBAJAXHandler';
        Data.Subaction      = 'AddValue';
        Data.Key            = \$('#$FieldName').val();
        Data.DynamicFieldID = $FieldID;

        var QueryString = Core.AJAX.SerializeForm(\$('#$AutoCompleteFieldName'), Data);
        \$.each(Data, function (Key, Value) {
            QueryString += ';' + encodeURIComponent(Key) + '=' + encodeURIComponent(Value);
        });

        \$('#$FieldName').data('AJAXRequest', \$.ajax({
            type: 'POST',
            url: Core.Config.Get('CGIHandle'),
            data: QueryString,
            dataType: 'html',
            async: false,
            success: function (Response) {
                if (Response) {
                    var Result = jQuery.parseJSON(Response);
                    \$('#$FieldName').val('');
                    while (\$('.InputField_Selection > input[name=$FieldName]').length >= $MaxArraySize) {
                        \$('.InputField_Selection > input[name=$FieldName]').last().siblings('div.Remove').find('a').trigger('click');
                    }
                    $IDCounterName++;
                    \$('#$ContainerFieldName').append(
                        '<div class="InputField_Selection" style="display:block;position:inherit;top:0px;">'
                        + '<input id="$ValueFieldName'
                        + $IDCounterName
                        + '" type="hidden" name="$FieldName" value="'
                        + Result.Key
                        + '" />'
                        + '<div class="Text" title="'
                        + Result.Title
                        + '">'
                        + Result.Value
                        + '</div>'
                        + '<div class="Remove"><a href="#" role="button" title="$TranslateRemoveSelection" tabindex="-1" aria-label="$TranslateRemoveSelection: '
                        + Result.Value
                        + '">x</a></div><div class="Clear"></div>'
                        + '</div>'
                    );
                    \$('#$ValueFieldName' + $IDCounterName).siblings('div.Remove').find('a').data('counter', $IDCounterName);
                    \$('#$ValueFieldName' + $IDCounterName).siblings('div.Remove').find('a').bind('click', function() {
                        \$('#$ValueFieldName' + \$(this).data('counter')).parent().remove();
                        if (\$('.InputField_Selection > input[name=$FieldName]').length == 0) {
                            \$('#$ContainerFieldName').hide().append(
                                '<input class="InputField_Dummy" type="hidden" name="$FieldName" value="" />'
                            );
                        }
                        if (\$('.InputField_Selection > input[name=$FieldName]').length < $MaxArraySize) {
                            \$('#$AutoCompleteFieldName').show();
                        }
                        \$('#$FieldName').trigger('change');
                        return false;
                    });
                    \$('#$ContainerFieldName').show();
                    \$('#$ContainerFieldName > .InputField_Dummy').remove();
                    \$('#$AutoCompleteFieldName').val('');
                    if (\$('.InputField_Selection > input[name=$FieldName]').length >= $MaxArraySize) {
                        \$('#$AutoCompleteFieldName').hide();
                    }
                    \$('#$FieldName').trigger('change');
                    return false;
                }
            },
            error: function (jqXHR, textStatus, errorThrown) {
                if (textStatus != 'abort') {
                    alert('Error thrown by AJAX: ' + textStatus + ': ' + errorThrown);
                }
            }
        }));
    });

    \$('#$ValidateFieldName').closest('form').bind('submit', function() {
        if ( \$('#$ValidateFieldName').hasClass('Error') ) {
            \$('label[for=$FieldName]').addClass('LabelError');
            \$('#$AutoCompleteFieldName').addClass('Error');
        } else {
            \$('label[for=$FieldName]').removeClass('LabelError');
            \$('#$AutoCompleteFieldName').removeClass('Error');
        }
    });

    if (\$('.InputField_Selection > input[name=$FieldName]').length == 0) {
        \$('#$ContainerFieldName').hide().append(
            '<input class="InputField_Dummy" type="hidden" name="$FieldName" value="" />'
        );
    }
    if (\$('.InputField_Selection > input[name=$FieldName]').length >= $MaxArraySize) {
        \$('#$AutoCompleteFieldName').hide();
    }
    Core.App.Subscribe('Event.AJAX.FormUpdate.Callback', function (Request, Response) {
        var Data = {};
        Data.Action         = 'DynamicFieldRemoteDBAJAXHandler';
        Data.Subaction      = 'PossibleValueCheck';
        Data.DynamicFieldID = $FieldID;

        var QueryString = Core.AJAX.SerializeForm(\$('#$AutoCompleteFieldName'), Data);
        \$.each(Data, function (Key, Value) {
            QueryString += ';' + encodeURIComponent(Key) + '=' + encodeURIComponent(Value);
        });

        if (\$('#$FieldName').data('PossibleValueCheck') != QueryString) {
            \$('#$FieldName').data('PossibleValueCheck', QueryString);
            Core.AJAX.FunctionCall(Core.Config.Get('CGIHandle'), QueryString, function (Response) {
                \$('.InputField_Selection > input[name=$FieldName]').each(function() {
                    var Found = 0;
                    var \$Element = \$(this);
                    \$.each(Response, function(Key, Value) {
                        if ( \$Element.val() == Value ) {
                            Found = 1;
                        }
                    });
                    if (Found == 0) {
                        \$Element.last().siblings('div.Remove').find('a').trigger('click');
                    }
                });
            }, undefined, false);
        }
    });
    
            }
            if(document.readyState === 'complete')
                initScript$AutoCompleteFieldName();
        </script>
END

    $Param{LayoutObject}->AddJSOnDocumentComplete( Code => <<"END");
    initScript$AutoCompleteFieldName();
END

    if ( $Param{Mandatory} ) {
        my $DivID = $FieldName . 'Error';

        my $FieldRequiredMessage = $Param{LayoutObject}->{LanguageObject}->Translate("This field is required.");

        # for client side validation
        $HTMLString .= <<"END";
        <div id="$DivID" class="TooltipErrorMessage">
            <p>
                $FieldRequiredMessage
            </p>
        </div>
END
    }

    if ( $Param{ServerError} ) {

        my $ErrorMessage = $Param{ErrorMessage} || 'This field is required.';
        $ErrorMessage = $Param{LayoutObject}->{LanguageObject}->Translate($ErrorMessage);
        my $DivID = $FieldName . 'ServerError';

        # for server side validation
        $HTMLString .= <<"END";
        <div id="$DivID" class="TooltipErrorMessage">
            <p>
                $ErrorMessage
            </p>
        </div>
END
    }

    if ( $Param{AJAXUpdate} ) {

        my $FieldSelector = '#' . $FieldName;

        my $FieldsToUpdate;
        if ( IsArrayRefWithData( $Param{UpdatableFields} ) ) {

            # Remove current field from updatable fields list
            my @FieldsToUpdate = grep { $_ ne $FieldName } @{ $Param{UpdatableFields} };

            # quote all fields, put commas in between them
            $FieldsToUpdate = join( ', ', map {"'$_'"} @FieldsToUpdate );
        }

        # add js to call FormUpdate()
        $Param{LayoutObject}->AddJSOnDocumentComplete( Code => <<"END");
\$('$FieldSelector').bind('change', function (Event) {
    var CurrentValue = '';
    \$('.InputField_Selection > input[name=$FieldName]').each(function() {
        if (CurrentValue.length > 0) {
            CurrentValue += ';';
        }
        CurrentValue += encodeURIComponent(\$(this).val());
    });
    if (\$(this).data('CurrentValue') != CurrentValue) {
        \$(this).data('CurrentValue', CurrentValue);
        Core.AJAX.FormUpdate(\$(this).parents('form'), 'AJAXUpdate', '$FieldName', [ $FieldsToUpdate ], function(){}, undefined, false);
    }
});
END
    }

    # call EditLabelRender on the common Driver
    my $LabelString = $Self->EditLabelRender(
        %Param,
        Mandatory => $Param{Mandatory} || '0',
        FieldName => $FieldName,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub EditFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    my $Value;

    # check if there is a Template and retrieve the dynamic field value from there
    if ( IsHashRefWithData( $Param{Template} ) ) {
        $Value = $Param{Template}->{$FieldName};
    }

    # otherwise get dynamic field value from the web request
    elsif (
        defined $Param{ParamObject}
        && ref $Param{ParamObject} eq 'Kernel::System::Web::Request'
        )
    {
        my @Data = $Param{ParamObject}->GetArray( Param => $FieldName );

        # delete empty values (can happen if the user has selected the "-" entry)
        my $Index = 0;
        ITEM:
        for my $Item ( sort @Data ) {

            if ( !$Item ) {
                splice( @Data, $Index, 1 );
                next ITEM;
            }
            $Index++;
        }

        $Value = \@Data;
    }

    if ( defined $Param{ReturnTemplateStructure} && $Param{ReturnTemplateStructure} eq 1 ) {
        return {
            $FieldName => $Value,
        };
    }

    # for this field the normal return an the ReturnValueStructure are the same
    return $Value;
}

sub EditFieldValueValidate {
    my ( $Self, %Param ) = @_;

    # get the field value from the http request
    my $Values = $Self->EditFieldValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ParamObject        => $Param{ParamObject},

        # not necessary for this Driver but place it for consistency reasons
        ReturnValueStructure => 1,
    );

    my $ServerError;
    my $ErrorMessage;

    # perform necessary validations
    if ( $Param{Mandatory} && !IsArrayRefWithData($Values) ) {
        return {
            ServerError => 1,
        };
    }

    if($Param{DynamicFieldConfig}->{Config}->{SaveDescription}){
        my $Result = {
            ServerError  => $ServerError,
            ErrorMessage => $ErrorMessage,
        };

        return $Result;
    }

    # get possible values list
    my $PossibleValues = $Self->_GetPossibleValues(%Param);

    # overwrite possible values if PossibleValuesFilter
    if ( defined $Param{PossibleValuesFilter} ) {
        $PossibleValues = $Param{PossibleValuesFilter}
    }

    CHECK:
    for my $Test ( @{$Values} ) {

        # validate if value is in possible values list (but let pass empty values)
        if ( $Test && !$PossibleValues->{$Test} ) {
            $ServerError  = 1;
            $ErrorMessage = 'The field content is invalid';
            last CHECK;
        }
    }

    # create resulting structure
    my $Result = {
        ServerError  => $ServerError,
        ErrorMessage => $ErrorMessage,
    };

    return $Result;
}

sub SearchFieldRender {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldID     = $Param{DynamicFieldConfig}->{ID};
    my $FieldName   = 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    my $Value;
    my @DefaultValue;

    if ( defined $Param{DefaultValue} ) {
        @DefaultValue = split /;/, $Param{DefaultValue};
    }

    # set the field value
    if (@DefaultValue) {
        $Value = \@DefaultValue;
    }

    # get the field value, this function is always called after the profile is loaded
    my $FieldValue = $Self->SearchFieldValueGet(%Param);

    # set values from ParamObject if present
    if ( IsArrayRefWithData($FieldValue) ) {
        $Value = $FieldValue;
    }

    # check and set class if necessary
    my $FieldClass = '';

    my $AutoCompleteFieldName = $FieldName . "_AutoComplete";
    my $ContainerFieldName    = $FieldName . "_Container";
    my $DisplayFieldName      = $FieldName . "_Display";
    my $IDCounterName         = $FieldName . "_IDCount";
    my $ValueFieldName        = $FieldName . "_";

    my $MaxArraySize          = $FieldConfig->{MaxArraySize} || 1;

    my $TranslateRemoveSelection = $Param{LayoutObject}->{LanguageObject}->Translate("Remove selection");

    my $HTMLString = <<"END";
    <div class="InputField_Container W50pc">
        <input id="$AutoCompleteFieldName" type="text" style="margin-bottom:2px;" />
        <div class="Clear"></div>
        <div id="$ContainerFieldName" class="InputField_InputContainer" style="display:block;">
END

    my $ValueCounter = 0;
    for my $Key ( @{ $Value } ) {
        next if (!$Key);
        $ValueCounter++;

        my $Label = $Self->ValueLookup(
            %Param,
            Key => $Key,
        );

        my $Title = $Label;
        if ( $Param{DynamicFieldConfig}->{Config}->{ShowKeyInTitle} ) {
            $Title .= ' (' . $Key . ')';
        }

        $HTMLString .= <<"END";
        <div class="InputField_Selection" style="display:block;position:inherit;top:0px;">
            <input id="$ValueFieldName$ValueCounter" type="hidden" name="$FieldName" value="$Key" />
            <div class="Text" title="$Title">$Label</div><div class="Remove"><a href="#" role="button" title="$TranslateRemoveSelection" tabindex="-1" aria-label="$TranslateRemoveSelection: $Label">x</a></div>
            <div class="Clear"></div>
        </div>
<script type="text/javascript">//<![CDATA[
    function Init$ValueFieldName$ValueCounter() {
        \$('#$ValueFieldName$ValueCounter').siblings('div.Remove').find('a').bind('click', function() {
            \$('#$ValueFieldName$ValueCounter').parent().remove();
            if (\$('input[name=$FieldName]').length == 0) {
                \$('#$ContainerFieldName').hide();
            }
            return false;
        });
    }
    function Wait$ValueFieldName$ValueCounter() {
        if (window.jQuery) {
            \$('#Attribute').bind('redraw.InputField', function() {
                Init$ValueFieldName$ValueCounter();
            });
            if (
                \$('form[name=compose] input[name=Action]').first().val() == 'AdminGenericAgent'
                && \$('form[name=compose] input[name=Subaction]').first().val() == 'UpdateAction'
            ) {
                Init$ValueFieldName$ValueCounter();
            }
        } else {
            window.setTimeout(Wait$ValueFieldName$ValueCounter, 1);
        }
    }
    window.setTimeout(Wait$ValueFieldName$ValueCounter, 0);
//]]></script>
END
    }

    $HTMLString .= <<"END";
        </div>
        <div class="Clear"></div>
    </div>
<script type="text/javascript">//<![CDATA[
    function Init$AutoCompleteFieldName() {
        var $IDCounterName = $ValueCounter;
        \$('#$AutoCompleteFieldName').autocomplete({
            delay: $FieldConfig->{QueryDelay},
            minLength: $FieldConfig->{MinQueryLength},
            source: function (Request, Response) {
                var Data = {};
                Data.Action         = 'DynamicFieldRemoteDBAJAXHandler';
                Data.Subaction      = 'Search';
                Data.ConfigOnly     = '1';
                Data.FieldPrefix    = 'Search_';
                Data.Search         = Request.term;
                Data.DynamicFieldID = $FieldID;

                var QueryString = Core.AJAX.SerializeForm(\$('#$AutoCompleteFieldName'), Data);
                \$.each(Data, function (Key, Value) {
                    QueryString += ';' + encodeURIComponent(Key) + '=' + encodeURIComponent(Value);
                });

                if (\$('#$AutoCompleteFieldName').data('AutoCompleteXHR')) {
                    \$('#$AutoCompleteFieldName').data('AutoCompleteXHR').abort();
                    \$('#$AutoCompleteFieldName').removeData('AutoCompleteXHR');
                }
                \$('#$AutoCompleteFieldName').data('AutoCompleteXHR', Core.AJAX.FunctionCall(Core.Config.Get('CGIHandle'), QueryString, function (Result) {
                    var Data = [];
                    \$.each(Result, function () {
                        Data.push({
                            key:   this.Key,
                            value: this.Value,
                            title: this.Title
                        });
                    });
                    \$('#$AutoCompleteFieldName').data('AutoCompleteData', Data);
                    \$('#$AutoCompleteFieldName').removeData('AutoCompleteXHR');
                    Response(Data);
                }).fail(function() {
                    Response(\$('#$AutoCompleteFieldName').data('AutoCompleteData'));
                }));
            },
            select: function (Event, UI) {
                $IDCounterName++;
                \$('#$ContainerFieldName').append(
                    '<div class="InputField_Selection" style="display:block;position:inherit;top:0px;">'
                    + '<input id="$ValueFieldName'
                    + $IDCounterName
                    + '" type="hidden" name="$FieldName" value="'
                    + UI.item.key
                    + '" />'
                    + '<div class="Text" title="'
                    + UI.item.title
                    + '">'
                    + UI.item.value
                    + '</div>'
                    + '<div class="Remove"><a href="#" role="button" title="$TranslateRemoveSelection" tabindex="-1" aria-label="$TranslateRemoveSelection: '
                    + UI.item.value
                    + '">x</a></div><div class="Clear"></div>'
                    + '</div>'
                );
                \$('#$ValueFieldName' + $IDCounterName).siblings('div.Remove').find('a').data('counter', $IDCounterName);
                \$('#$ValueFieldName' + $IDCounterName).siblings('div.Remove').find('a').bind('click', function() {
                    \$('#$ValueFieldName' + \$(this).data('counter')).parent().remove();
                    if (\$('input[name=$FieldName]').length == 0) {
                        \$('#$ContainerFieldName').hide();
                    }
                    return false;
                });
                \$('#$ContainerFieldName').show();
                \$('#$AutoCompleteFieldName').val('');
                Event.preventDefault();
                return false;
            },
        });
        \$('#$AutoCompleteFieldName').blur(function() {
            \$(this).val('');
        });

        if (\$('input[name=$FieldName]').length == 0) {
            \$('#$ContainerFieldName').hide();
        }
    }
    function Wait$AutoCompleteFieldName() {
        if (window.jQuery) {
            \$('#Attribute').bind('redraw.InputField', function() {
                Init$AutoCompleteFieldName();
            });
            if (
                \$('form[name=compose] input[name=Action]').first().val() == 'AdminGenericAgent'
                && \$('form[name=compose] input[name=Subaction]').first().val() == 'UpdateAction'
            ) {
                Init$AutoCompleteFieldName();
            }
        } else {
            window.setTimeout(Wait$AutoCompleteFieldName, 1);
        }
    }
    window.setTimeout(Wait$AutoCompleteFieldName, 0);
//]]></script>
END

    # call EditLabelRender on the common Driver
    my $LabelString = $Self->EditLabelRender(
        %Param,
        FieldName => $FieldName,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub SearchFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $Value;

    # get dynamic field value from param object
    if ( defined $Param{ParamObject} ) {
        my @FieldValues = $Param{ParamObject}->GetArray(
            Param => 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name}
        );

        $Value = \@FieldValues;
    }

    # otherwise get the value from the profile
    elsif ( defined $Param{Profile} ) {
        $Value = $Param{Profile}->{ 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} };
    }
    else {
        return;
    }

    if ( defined $Param{ReturnProfileStructure} && $Param{ReturnProfileStructure} eq 1 ) {
        return {
            'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} => $Value,
        };
    }

    return $Value;
}

sub SearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    # get field value
    my $Value = $Self->SearchFieldValueGet(%Param);

    my $DisplayValue;

    if ( defined $Value && !$Value ) {
        $DisplayValue = '';
    }

    if ($Value) {
        if ( ref $Value eq 'ARRAY' ) {

            my @DisplayItemList;
            for my $Item ( @{$Value} ) {

                # set the display value
                my $DisplayItem = $Self->ValueLookup(
                    %Param,
                    Key => $Item,
                );

                push @DisplayItemList, $DisplayItem;
            }

            # combine different values into one string
            $DisplayValue = join ' + ', @DisplayItemList;
        }
        else {

            # set the display value
            $DisplayValue = $Self->ValueLookup(
                %Param,
                Key => $Value,
            );
        }
    }

    # return search parameter structure
    return {
        Parameter => {
            Equals => $Value,
        },
        Display => $DisplayValue,
    };
}

sub SearchSQLGet {
    my ( $Self, %Param ) = @_;

    my %Operators = (
        Equals            => '=',
        GreaterThan       => '>',
        GreaterThanEquals => '>=',
        SmallerThan       => '<',
        SmallerThanEquals => '<=',
    );

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    if ( $Operators{ $Param{Operator} } ) {
        my $SQL = " $Param{TableAlias}.value_text $Operators{$Param{Operator}} '";
        $SQL .= $DBObject->Quote( $Param{SearchTerm} ) . "' ";
        return $SQL;
    }

    if ( $Param{Operator} eq 'Like' ) {

        my $SQL = $DBObject->QueryCondition(
            Key   => "$Param{TableAlias}.value_text",
            Value => $Param{SearchTerm},
        );

        return $SQL;
    }

    $Kernel::OM->Get('Kernel::System::Log')->Log(
        'Priority' => 'error',
        'Message'  => "Unsupported Operator $Param{Operator}",
    );

    return;
}

sub SearchSQLOrderFieldGet {
    my ( $Self, %Param ) = @_;

    return "$Param{TableAlias}.value_text";
}

sub ReadableValueRender {
    my ( $Self, %Param ) = @_;

    # set Value and Title variables
    my $Value = '';
    my $Title = '';

    # check value
    my @Values;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }

    my @ReadableValues;

    VALUEITEM:
    for my $Item (@Values) {
        next VALUEITEM if !$Item;

        push @ReadableValues, $Item;
    }

    # set new line separator
    my $ItemSeparator = $Param{DynamicFieldConfig}->{Config}->{ItemSeparator} || ', ';

    # Output transformations
    $Value = join( $ItemSeparator, @ReadableValues );
    $Title = $Value;

    # cut strings if needed
    if ( $Param{ValueMaxChars} && length($Value) > $Param{ValueMaxChars} ) {
        $Value = substr( $Value, 0, $Param{ValueMaxChars} ) . '...';
    }
    if ( $Param{TitleMaxChars} && length($Title) > $Param{TitleMaxChars} ) {
        $Title = substr( $Title, 0, $Param{TitleMaxChars} ) . '...';
    }

    # create return structure
    my $Data = {
        Value => $Value,
        Title => $Title,
    };

    return $Data;
}

sub DisplayValueRender {
    my ( $Self, %Param ) = @_;

    # set HTMLOuput as default if not specified
    if ( !defined $Param{HTMLOutput} ) {
        $Param{HTMLOutput} = 1;
    }

    # get raw Value strings from field value
    my @Keys;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Keys = @{ $Param{Value} };
    }
    else {
        @Keys = ( $Param{Value} );
    }

    my @Values;
    my @Titles;

    for my $Key (@Keys) {

        $Key ||= '';

        my $EntryValue = $Self->ValueLookup(
            %Param,
            Key => $Key,
        );

        # set title as value after update and before limit
        my $EntryTitle = $EntryValue;
        if ( $Param{DynamicFieldConfig}->{Config}->{ShowKeyInTitle} ) {
            $EntryTitle .= ' (' . $Key . ')';
        }

        # HTMLOuput transformations
        if ( $Param{HTMLOutput} ) {
            $EntryValue = $Param{LayoutObject}->Ascii2Html(
                Text => $EntryValue,
                Max => $Param{ValueMaxChars} || '',
            );

            $EntryTitle = $Param{LayoutObject}->Ascii2Html(
                Text => $EntryTitle,
                Max => $Param{TitleMaxChars} || '',
            );

            # set field link form config
            my $HasLink = 0;
            my $OldValue;
            if (
                $Param{LayoutObject}->{UserType} eq 'User'
                && $Param{DynamicFieldConfig}->{Config}->{AgentLink}
                )
            {
                $OldValue = $EntryValue;
                $EntryValue
                    = '<a href="'
                    . $Param{DynamicFieldConfig}->{Config}->{AgentLink}
                    . '" title="'
                    . $EntryTitle
                    . '" target="_blank" class="DynamicFieldLink">'
                    . $EntryValue . '</a>';
                $HasLink = 1;
            }
            elsif (
                $Param{LayoutObject}->{UserType} eq 'Customer'
                && $Param{DynamicFieldConfig}->{Config}->{CustomerLink}
                )
            {
                $OldValue = $EntryValue;
                $EntryValue
                    = '<a href="'
                    . $Param{DynamicFieldConfig}->{Config}->{CustomerLink}
                    . '" title="'
                    . $EntryTitle
                    . '" target="_blank" class="DynamicFieldLink">'
                    . $EntryValue . '</a>';
                $HasLink = 1;
            }
            if ($HasLink) {

                # Replace <RDB_Key>
                if ( $EntryValue =~ /<RDB_Key>/ ) {
                    my $Replace = $Param{LayoutObject}->LinkEncode($Key);
                    $EntryValue =~ s/<RDB_Key>/$Replace/g;
                }

                # Replace <RDB_Value>
                if ( $EntryValue =~ /<RDB_Value>/ ) {
                    my $Replace = $Param{LayoutObject}->LinkEncode($OldValue);
                    $EntryValue =~ s/<RDB_Value>/$Replace/g;
                }

                # Replace <RDB_Title>
                if ( $EntryValue =~ /<RDB_Title>/ ) {
                    my $Replace = $Param{LayoutObject}->LinkEncode($EntryTitle);
                    $EntryValue =~ s/<RDB_Title>/$Replace/g;
                }

                # Replace <SessionID>
                if ( $EntryValue =~ /<SessionID>/ ) {
                    my $Replace = $Param{LayoutObject}->{SessionID};
                    $EntryValue =~ s/<SessionID>/$Replace/g;
                }
            }
        }
        else {
            if ( $Param{ValueMaxChars} && length($EntryValue) > $Param{ValueMaxChars} ) {
                $EntryValue = substr( $EntryValue, 0, $Param{ValueMaxChars} ) . '...';
            }
            if ( $Param{TitleMaxChars} && length($EntryTitle) > $Param{TitleMaxChars} ) {
                $EntryTitle = substr( $EntryTitle, 0, $Param{TitleMaxChars} ) . '...';
            }
        }

        push ( @Values, $EntryValue );
        push ( @Titles, $EntryTitle );
    }

    # set item separator
    my $ItemSeparator = $Param{DynamicFieldConfig}->{Config}->{ItemSeparator} || ', ';

    my $Value = join( $ItemSeparator, @Values );
    my $Title = join( $ItemSeparator, @Titles );

    # this field type does not support the Link Feature in normal way. Links are provided via Value in HTMLOutput
    my $Link;

    # create return structure
    my $Data = {
        Value => $Value,
        Title => $Title,
        Link  => $Link,
    };

    return $Data;
}

sub StatsFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    # set PossibleValues
    my $Values = $Self->PossibleValuesGet(%Param);

    # get historical values from database
    my $HistoricalValues = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->HistoricalValueGet(
        FieldID   => $Param{DynamicFieldConfig}->{ID},
        ValueType => 'Text,',
    );

    # add historic values to current values (if they don't exist anymore)
    for my $Key ( sort keys %{$HistoricalValues} ) {
        if ( !$Values->{$Key} ) {
            my $Value = $Self->ValueLookup(
                %Param,
                Key => $Key,
            );
            $Values->{$Key} = $Value;
        }
    }

    # use PossibleValuesFilter if defined
    $Values = $Param{PossibleValuesFilter} if ( defined($Param{PossibleValuesFilter}) );

    return {
        Values             => $Values,
        Name               => $Param{DynamicFieldConfig}->{Label},
        Element            => 'DynamicField_' . $Param{DynamicFieldConfig}->{Name},
        Block              => 'MultiSelectField',
    };
}

sub StatsSearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    my $Operator = 'Equals';
    my $Value    = $Param{Value};

    return {
        $Operator => $Value,
    };
}

sub ColumnFilterValuesGet {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};

    # get column filter values from database
    my $ColumnFilterValues = $Kernel::OM->Get('Kernel::System::Ticket::ColumnFilter')->DynamicFieldFilterValuesGet(
        TicketIDs => $Param{TicketIDs},
        FieldID   => $Param{DynamicFieldConfig}->{ID},
        ValueType => 'Text',
    );

    # get the display value if still exist in dynamic field configuration
    for my $Key ( sort ( keys ( %{$ColumnFilterValues} ) ) ) {
        my $Value = $Self->ValueLookup(
            %Param,
            Key => $Key,
        );
        $ColumnFilterValues->{$Key} = $Value;
    }

    return $ColumnFilterValues;
}

sub _GetPossibleValues {
    my ( $Self, %Param ) = @_;

    my $PossibleValues;

    # create cache object
    if ( $Param{DynamicFieldConfig}->{Config}->{CacheTTL} && $Param{DynamicFieldConfig}->{Config}->{CachePossibleValues} ) {

        # set cache type
        $Self->{CacheType} = 'DynamicField_RemoteDB_' . $Param{DynamicFieldConfig}->{Name};

        $PossibleValues = $Kernel::OM->Get('Kernel::System::Cache')->Get(
            Type => $Self->{CacheType},
            Key  => "GetPossibleValues",
        );
        return $PossibleValues if $PossibleValues;
    }

    my $DFRemoteDBObject;

    if ( $Param{DynamicFieldConfig}->{Config}->{UseOTRSDB} ) {
        $DFRemoteDBObject = $Kernel::OM->Get('Kernel::System::DB');
    }
    else {
        $DFRemoteDBObject = Kernel::System::DFRemoteDB->new(
            DatabaseDSN  => $Param{DynamicFieldConfig}->{Config}->{DatabaseDSN},
            DatabaseUser => $Param{DynamicFieldConfig}->{Config}->{DatabaseUser},
            DatabasePw   => $Param{DynamicFieldConfig}->{Config}->{DatabasePw},
            %{ $Self },
        );
    }

    my %Constrictions = ();
    if ($Param{DynamicFieldConfig}->{Config}->{Constrictions}) {
        my @Constrictions = split(/[\n\r]+/, $Param{DynamicFieldConfig}->{Config}->{Constrictions});
        RESTRICTION:
        for my $Constriction ( @Constrictions ) {
            my @ConstrictionRule = split(/::/, $Constriction);
            next RESTRICTION if (
                scalar(@ConstrictionRule) != 4
                || $ConstrictionRule[0] eq ""
                || $ConstrictionRule[1] eq ""
                || $ConstrictionRule[2] eq ""
            );

            if (
                $ConstrictionRule[1] eq 'Configuration'
            ) {
                $Constrictions{$ConstrictionRule[0]} = $ConstrictionRule[2];
            }
        }
    }

    my $SQL = 'SELECT '
        . $Param{DynamicFieldConfig}->{Config}->{DatabaseFieldKey}
        . ', '
        . $Param{DynamicFieldConfig}->{Config}->{DatabaseFieldValue}
        . ' FROM '
        . $Param{DynamicFieldConfig}->{Config}->{DatabaseTable};

    $DFRemoteDBObject->Prepare(
        SQL   => $SQL,
    );

    while (my @Row = $DFRemoteDBObject->FetchrowArray()) {
        my $Key   = $Row[0] || '';
        my $Value = $Row[1] || '';
        $PossibleValues->{$Key} = $Value;
    }

    # cache request
    if ( $Param{DynamicFieldConfig}->{Config}->{CacheTTL} && $Param{DynamicFieldConfig}->{Config}->{CachePossibleValues} ) {
        $Kernel::OM->Get('Kernel::System::Cache')->Set(
            Type  => $Self->{CacheType},
            Key   => "GetPossibleValues",
            Value => $PossibleValues,
            TTL   => $Param{DynamicFieldConfig}->{Config}->{CacheTTL},
        );
    }

    return $PossibleValues;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
